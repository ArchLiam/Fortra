"""Apply SC-3293 page-level Required edits to Contact_Record_Page_Three_Column.

1. Flip uiBehavior on 3 existing fieldInstances: none -> required.
2. Add 3 new fieldInstances with uiBehavior=required:
   - Record.FirstName (after Record.Name composite)
   - Record.Workday_MobilePhone_Device_Type__c (after Country)
   - Record.Workday_MobilePhone_Usage_Type__c (after Device_Type)
"""

import re
from pathlib import Path

FP = Path("force-app/main/default/flexipages/Contact_Record_Page_Three_Column.flexipage-meta.xml")
xml = FP.read_text()


def flip_ui_behavior(xml_text: str, field_api: str) -> str:
    """For the <fieldInstance> whose <fieldItem> is Record.<field_api>, flip uiBehavior to required."""
    pat = re.compile(
        r"(<fieldInstance>\s*<fieldInstanceProperties>\s*<name>uiBehavior</name>\s*<value>)none(</value>\s*</fieldInstanceProperties>\s*<fieldItem>Record\."
        + re.escape(field_api)
        + r"</fieldItem>)"
    )
    new_text, n = pat.subn(r"\1required\2", xml_text, count=1)
    assert n == 1, f"Did not find exactly one occurrence to flip for {field_api} (n={n})"
    return new_text


def insert_after_field(xml_text: str, anchor_api: str, new_item: str) -> str:
    """Insert a new <itemInstances>...</itemInstances> block immediately after the
    anchor field's enclosing </itemInstances>. Each fieldInstance is wrapped in its
    own <itemInstances> parent per the FlexiPage schema."""
    anchor_field = re.compile(
        r"<fieldInstance>\s*<fieldInstanceProperties>\s*<name>uiBehavior</name>\s*<value>[^<]+</value>\s*</fieldInstanceProperties>\s*<fieldItem>Record\."
        + re.escape(anchor_api)
        + r"</fieldItem>\s*<identifier>[^<]+</identifier>\s*</fieldInstance>"
    )
    m = anchor_field.search(xml_text)
    assert m, f"Anchor not found: {anchor_api}"
    # Walk forward to the wrapping </itemInstances>
    wrapper_close = xml_text.find("</itemInstances>", m.end()) + len("</itemInstances>")
    # Determine indentation of the wrapper's opening <itemInstances>
    wrapper_open = xml_text.rfind("<itemInstances>", 0, m.start())
    line_start = xml_text.rfind("\n", 0, wrapper_open) + 1
    indent = xml_text[line_start:wrapper_open]
    insertion = "\n" + indent + new_item.strip()
    return xml_text[:wrapper_close] + insertion + xml_text[wrapper_close:]


def field_instance(field_api: str) -> str:
    """Generate an <itemInstances>+<fieldInstance> XML block for a Contact field with uiBehavior=required."""
    return (
        "<itemInstances>\n"
        "            <fieldInstance>\n"
        "                <fieldInstanceProperties>\n"
        "                    <name>uiBehavior</name>\n"
        "                    <value>required</value>\n"
        "                </fieldInstanceProperties>\n"
        f"                <fieldItem>Record.{field_api}</fieldItem>\n"
        f"                <identifier>Record{field_api}Field</identifier>\n"
        "            </fieldInstance>\n"
        "        </itemInstances>"
    )


# --- 1. Flip uiBehavior on the 3 existing fields ---
for fld in [
    "Business_Entity_Contact_ID__c",
    "MobilePhone",
    "Workday_MobilePhone_Country_ISO_Code__c",
]:
    xml = flip_ui_behavior(xml, fld)
    print(f"flipped uiBehavior=required: {fld}")

# --- 2. Insert new fieldInstances ---
# Note: FirstName cannot be added as a separate fieldInstance because Record.Name
# is already on the page; Name is a composite that owns FirstName/LastName/Salutation,
# so the Lightning page schema rejects a duplicate Record.FirstName. Record.Name
# already has uiBehavior=required (covers LastName per SF platform).
#
# Workday_MobilePhone_Device_Type__c goes after Country
xml = insert_after_field(
    xml,
    "Workday_MobilePhone_Country_ISO_Code__c",
    field_instance("Workday_MobilePhone_Device_Type__c"),
)
print("inserted: Workday_MobilePhone_Device_Type__c after Country")

# Workday_MobilePhone_Usage_Type__c goes after Device_Type (which we just inserted)
xml = insert_after_field(
    xml,
    "Workday_MobilePhone_Device_Type__c",
    field_instance("Workday_MobilePhone_Usage_Type__c"),
)
print("inserted: Workday_MobilePhone_Usage_Type__c after Device_Type")

FP.write_text(xml)
print("\nDone.")
