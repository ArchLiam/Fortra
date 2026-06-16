List<Order> os = [SELECT Id, Status, Description FROM Order WHERE Description IN ('SC3415TEST_DUP', 'SC3415TEST_OK')];
for (Order o : os) { o.Status = 'Activated'; }
try {
    update os;
    System.debug('SC3415TEST_ACTIVATED count=' + os.size());
} catch (Exception e) {
    System.debug('SC3415TEST_ACTIVATE_ERR ' + e.getMessage());
}
