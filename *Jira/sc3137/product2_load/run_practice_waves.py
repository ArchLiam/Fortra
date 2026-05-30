#!/usr/bin/env python3
"""Insert pse__Practice__c records in topological waves.
Wave 1 (Global Practice) is already in MB.
Waves 2-4 insert children, populating Parent + Global Practice FKs using the
running Name -> MB-Id map.
"""
import json, csv, subprocess, os, sys, time

WORK = '/Users/liamjeong/sc3137/product2_load'
MB_USER = '005aZ00000WzoqHQAR'  # liam.jeong.c@fortra.com.mergebuild

with open('/tmp/prac_uat_closure.json') as f:
    RECS = json.load(f)['result']['records']
REC_BY_ID = {r['Id']: r for r in RECS}

with open('/tmp/prac_uat_id_metadata.json') as f:
    META = json.load(f)
UAT_NAME_BY_ID = META['name_by_id']
UAT_PARENT_BY_ID = META['parent_by_id']
UAT_GLOBAL_BY_ID = META['global_by_id']

with open('/tmp/prac_waves.json') as f:
    WAVES = {int(k): v for k, v in json.load(f).items()}

with open('/tmp/prac_describe_mb.json') as f:
    mb = json.load(f)
MB_FIELDS = {f['name']: f for f in mb['result']['fields']}
MB_CREATEABLE_FK = {n for n, f in MB_FIELDS.items() if f.get('createable') and f.get('type') == 'reference'}

with open('/tmp/prac_query_fields.txt') as f:
    INTERSECT = [c for c in f.read().split(',') if c != 'Id']


def query_mb_practices():
    """Return Name -> MB Id map from current MB state."""
    out = subprocess.run(
        ['sf', 'data', 'query', '-o', 'MergeBuild',
         '-q', 'SELECT Id, Name FROM pse__Practice__c',
         '--json'],
        capture_output=True, text=True, check=True
    )
    text = out.stdout
    if text.startswith(' '):
        text = '\n'.join(text.split('\n')[1:])
    d = json.loads(text)
    return {r['Name']: r['Id'] for r in d['result']['records']}


def build_wave_payload(wave_ids, name_to_mb, payload_path):
    rows = []
    for uid in wave_ids:
        r = REC_BY_ID[uid]
        row = {}
        for fname in INTERSECT:
            v = r.get(fname)
            if fname == 'OwnerId':
                row[fname] = MB_USER
            elif fname == 'pse__Parent_Practice__c':
                p_uat = UAT_PARENT_BY_ID.get(uid)
                if p_uat:
                    p_name = UAT_NAME_BY_ID[p_uat]
                    row[fname] = name_to_mb.get(p_name, '')
                else:
                    row[fname] = ''
            elif fname == 'pse__Global_Practice__c':
                g_uat = UAT_GLOBAL_BY_ID.get(uid)
                if g_uat:
                    g_name = UAT_NAME_BY_ID[g_uat]
                    row[fname] = name_to_mb.get(g_name, '')
                else:
                    row[fname] = ''
            elif fname in MB_CREATEABLE_FK:
                row[fname] = ''
            else:
                row[fname] = '' if v is None else v
        # Sanity check
        if not row['pse__Parent_Practice__c']:
            raise RuntimeError(f"Wave row {r['Name']} has no Parent_Practice__c mapped — aborting")
        rows.append(row)

    with open(payload_path, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=INTERSECT, lineterminator='\r\n')
        w.writeheader()
        w.writerows(rows)
    return len(rows)


def insert_wave(payload_path, log_path):
    cmd = ['sf', 'data', 'import', 'bulk',
           '-o', 'MergeBuild',
           '-s', 'pse__Practice__c',
           '-f', payload_path,
           '--line-ending', 'CRLF',
           '-w', '15']
    with open(log_path, 'w') as logf:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        logf.write("STDOUT:\n" + proc.stdout + "\nSTDERR:\n" + proc.stderr)
    text = proc.stdout + proc.stderr
    # Strip ANSI escape codes
    import re
    clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', text)
    return clean


def parse_summary(log_text):
    """Pull final 'Processed/Successful/Failed' counts from log."""
    import re
    proc = re.findall(r'Processed records:\s*(\d+)', log_text)
    succ = re.findall(r'Successful records:\s*(\d+)', log_text)
    fail = re.findall(r'Failed records:\s*(\d+)', log_text)
    job = re.findall(r'750[A-Za-z0-9]{14,15}', log_text)
    return {
        'processed': int(proc[-1]) if proc else None,
        'successful': int(succ[-1]) if succ else None,
        'failed': int(fail[-1]) if fail else None,
        'job_id': job[-1] if job else None,
    }


def main():
    name_to_mb = query_mb_practices()
    print(f"Starting MB Practice map: {len(name_to_mb)} entries", flush=True)
    for n, i in name_to_mb.items():
        print(f"  {n}: {i}", flush=True)

    for wave_num in [2, 3, 4]:
        depth = wave_num - 1
        wave_ids = WAVES[depth]
        print(f"\n=== Wave {wave_num} (depth {depth}): {len(wave_ids)} Practices ===", flush=True)
        payload_path = os.path.join(WORK, f'practice_wave{wave_num}_payload.csv')
        log_path = os.path.join(WORK, f'practice_wave{wave_num}_insert.log')

        n_rows = build_wave_payload(wave_ids, name_to_mb, payload_path)
        print(f"  Built payload: {n_rows} rows -> {payload_path}", flush=True)
        log_text = insert_wave(payload_path, log_path)
        summary = parse_summary(log_text)
        print(f"  Insert result: {summary}", flush=True)

        if summary.get('successful') != n_rows:
            print(f"!! Wave {wave_num} FAILED 100% threshold (expected {n_rows}, got {summary.get('successful')})", flush=True)
            print("Halting.", flush=True)
            sys.exit(1)

        # Refresh name_to_mb map for next wave
        name_to_mb = query_mb_practices()
        print(f"  MB Practice map after wave {wave_num}: {len(name_to_mb)} entries", flush=True)

    print(f"\nAll waves complete. Final MB Practice count: {len(name_to_mb)}", flush=True)
    if len(name_to_mb) != 25:
        print(f"!! WARNING: expected 25, got {len(name_to_mb)}", flush=True)


if __name__ == '__main__':
    main()
