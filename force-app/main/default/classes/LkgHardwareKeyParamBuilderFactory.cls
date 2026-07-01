public with sharing class LkgHardwareKeyParamBuilderFactory {
    public static ILkgHardwareKeyParamBuilder getBuilder(String silo) {
        if (String.isBlank(silo)) {
            return null;
        }

        switch on silo.toLowerCase() {
            when 'automate' {
                return new LkgHardwareAutomateKeyParamBuilder();
            }
            when else {
                return null;
            }
        }
    }
}