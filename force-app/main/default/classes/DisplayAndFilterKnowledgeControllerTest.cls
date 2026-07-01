@isTest
private class DisplayAndFilterKnowledgeControllerTest {

    @isTest
    static void DisplayAndFilterKnowledgeControllerTest() {
        List<Knowledge__kav> testKnowledgeArticles = new List<Knowledge__kav>();
        for (Integer i = 1; i <= 5; i++) {
            testKnowledgeArticles.add(new Knowledge__kav(
                Title = 'Test Article ' + i,
				UrlName = 'test-article-' + i
            ));
        }
        insert testKnowledgeArticles;

        Test.startTest();
		List<Knowledge__kav> returnedArticles = DisplayAndFilterKnowledgeController.getKnowledgeArticles();
        Test.stopTest();

        // Assert
        // System.assertEquals(5, returnedArticles.size());
        // System.assertEquals('Test Article 1', returnedArticles[0].Title);
    }
}