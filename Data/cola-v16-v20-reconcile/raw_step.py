import sys, re
NS='{http://soap.sforce.com/2006/04/metadata}'
import xml.etree.ElementTree as ET
def t(el,tag):
    c=el.find(NS+tag); return c.text if c is not None else None
path=sys.argv[1]; want_label=sys.argv[2]; occ=int(sys.argv[3]) if len(sys.argv)>3 else 0
r=ET.parse(path).getroot()
seen=0
for st in r.findall(NS+'steps'):
    if t(st,'label')==want_label:
        if seen==occ:
            ET.indent(st, space='  ')
            x=ET.tostring(st, encoding='unicode')
            print(x.replace(NS,''))
            break
        seen+=1
