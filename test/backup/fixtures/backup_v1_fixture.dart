// Independent external v1 contract. Do not derive from persistence or codecs.
const backupV1Fixture = r'''
{
  "format": "keep-my-car-backup",
  "exportFormatVersion": 1,
  "createdAt": "2026-10-01T01:00:00.000Z",
  "data": {
    "ownerBirthMonth": "1970-04",
    "car": {
      "name": "愛車 🚗",
      "firstRegistrationMonth": "2018-08",
      "currentMileageKm": 45000,
      "mileageCheckedMonth": "2026-09",
      "annualMileageKm": 4000
    },
    "planConditions": {
      "currentMileageKm": 45000,
      "annualMileageKm": 4000,
      "ownershipTargetAge": 70,
      "currentCarFundYen": 500000,
      "reserveTargetAge": 65,
      "largeRepairReserveYen": 2000000
    },
    "plannedExpenses": [
      {"id": 17, "name": "タイヤ交換", "amountYen": 80000,
       "plannedMonth": "2027-04", "basis": "quoted",
       "memo": "見積もり確認済み 🚗", "status": "planned"},
      {"id": -3, "name": "過去の予定", "amountYen": 0,
       "plannedMonth": "2000-01", "basis": "selfEstimate",
       "memo": null, "status": "completed"},
      {"id": 0, "name": "タイヤ交換", "amountYen": 80000,
       "plannedMonth": "2027-04", "basis": "placeholder",
       "memo": null, "status": "planned"}
    ]
  }
}
''';
