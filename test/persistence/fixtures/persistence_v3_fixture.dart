// Independent wire fixture; deliberately not produced by the codec under test.
const photoIdV3 = '550e8400-e29b-41d4-a716-446655440000';
const persistenceV3Fixture = r'''
{
  "formatVersion": 3,
  "photoId": "550e8400-e29b-41d4-a716-446655440000",
  "ownerBirthMonth": "1970-04",
  "car": {
    "name": "メルセデスAMG E53",
    "firstRegistrationMonth": "2018-08",
    "currentMileageKm": 45000,
    "mileageCheckedMonth": "2026-09",
    "annualMileageKm": 4000
  },
  "planConditions": {
    "fundingPlanEnabled": true,
    "currentMileageKm": 45000,
    "annualMileageKm": 4000,
    "ownershipTargetAge": 70,
    "currentCarFundYen": 500000,
    "reserveTargetAge": 65,
    "largeRepairReserveYen": 2000000
  },
  "plannedExpenses": [
    {"id":1,"name":"12Vバッテリー","amountYen":80000,"plannedMonth":"2027-04","basis":"placeholder","memo":null,"status":"planned"},
    {"id":2,"name":"タイヤ","amountYen":220000,"plannedMonth":"2028-08","basis":"placeholder","memo":null,"status":"planned"},
    {"id":3,"name":"ブレーキ一式","amountYen":800000,"plannedMonth":"2031-06","basis":"placeholder","memo":null,"status":"planned"},
    {"id":4,"name":"48Vバッテリー","amountYen":500000,"plannedMonth":"2034-09","basis":"placeholder","memo":null,"status":"planned"},
    {"id":5,"name":"足回り","amountYen":700000,"plannedMonth":"2037-08","basis":"placeholder","memo":null,"status":"planned"},
    {"id":6,"name":"タイヤ","amountYen":250000,"plannedMonth":"2039-04","basis":"placeholder","memo":null,"status":"planned"}
  ]
}
''';
