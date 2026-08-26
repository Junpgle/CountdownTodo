# Medal recommendation

Status: implemented rule-based and ML-assisted recommendation paths. Last
reviewed: 2026-08-25.

## Source of truth

`MedalRecommendationService` currently defines **100** `MedalInfo` entries. Do
not duplicate the complete catalog in documentation; names, thresholds,
categories and display metadata in that service are authoritative.

## Recommendation flow

1. Rule-based recommendation ranks unfinished medals by remaining progress and
   returns the nearest three.
2. `recommendNextML` builds behavioral features and applies a Thompson-sampling
   bandit path to produce a personalized result and reasons.
3. The personal timeline first has a quick rule result, then can replace/enrich
   it with the asynchronous ML result and displays an ML indicator.
4. Recommendation state is persisted in the `medal_recommendations` table,
   introduced by the schema-v27 migration.

Coverage exists in `test/medal_recommendation_service_test.dart` (catalog and
recommendation behavior). When adding medals, update the service, verify unique
IDs and reachable thresholds, and expand the focused tests rather than updating
a copied list here.
