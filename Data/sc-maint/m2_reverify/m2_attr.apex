// Which AttributeDefinitionCode exists? MTD vs MDT
List<AttributeDefinition> ads = [SELECT Id, Name, Code, DeveloperName FROM AttributeDefinition WHERE Code IN ('MTD','MDT','MDP','MTP') ];
System.debug('=== AttributeDefinition with codes MTD/MDT ===');
for (AttributeDefinition a : ads) System.debug('AD Code='+a.Code+' Name='+a.Name+' Dev='+a.DeveloperName+' Id='+a.Id);
// broader: any AD whose code contains M and (T/D)
List<AttributeDefinition> ads2 = [SELECT Id, Name, Code, DeveloperName FROM AttributeDefinition WHERE Code LIKE 'M%' ORDER BY Code];
System.debug('=== All AttributeDefinition codes starting with M ===');
for (AttributeDefinition a : ads2) System.debug('AD Code='+a.Code+' Name='+a.Name+' Dev='+a.DeveloperName);
