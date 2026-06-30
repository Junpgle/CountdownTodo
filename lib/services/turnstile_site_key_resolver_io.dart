String resolveTurnstileSiteKey({
  required bool isTest,
  required String testSiteKey,
  required String productionSiteKey,
  required bool useProductionOnLocalWeb,
}) {
  return isTest ? testSiteKey : productionSiteKey;
}
