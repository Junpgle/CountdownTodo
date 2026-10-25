class CountdownTodoTutorialLinks {
  CountdownTodoTutorialLinks._();

  static final Uri aiAssistantAdvanced = _tutorialUri('tZ1HN7edMEsGOQqotd3dvB');
  static final Uri widgetFeatures = _tutorialUri('TJFZqAVdsLn8sI2ZIF6FVe');

  static Uri _tutorialUri(String pageId) => Uri(
    scheme: 'https',
    host: 'docs.qq.com',
    path: '/aio/DRmZzZHBsdkVBdENi',
    queryParameters: {'p': pageId, 'client_hint': '0'},
  );
}
