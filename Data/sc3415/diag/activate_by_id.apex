List<Order> os = [SELECT Id, Status FROM Order WHERE Id IN ('801WC00000kpGHyYAM', '801WC00000kpGHzYAM')];
for (Order o : os) { o.Status = 'Activated'; }
try {
    update os;
    System.debug('SC3415TEST_ACTIVATED count=' + os.size());
} catch (Exception e) {
    System.debug('SC3415TEST_ACTIVATE_ERR ' + e.getMessage());
}
