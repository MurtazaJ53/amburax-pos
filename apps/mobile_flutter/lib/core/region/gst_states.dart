/// India's GST state codes.
///
/// The registration form asked for this as a two-digit box labelled "State".
/// Nobody knows their state code by heart, so it invited a state name, or "7"
/// where the field means "07" — and rejected neither. The consequence is
/// silent: this code decides whether a bill is taxed CGST+SGST or IGST, so a
/// wrong value mis-files every invoice the shop ever issues.
///
/// The codes are the first two digits of a GSTIN, which is the check a
/// shopkeeper can perform on themselves.
class GstState {
  const GstState(this.code, this.name);
  final String code;
  final String name;
}

const List<GstState> kGstStates = <GstState>[
  GstState('01', 'Jammu & Kashmir'),
  GstState('02', 'Himachal Pradesh'),
  GstState('03', 'Punjab'),
  GstState('04', 'Chandigarh'),
  GstState('05', 'Uttarakhand'),
  GstState('06', 'Haryana'),
  GstState('07', 'Delhi'),
  GstState('08', 'Rajasthan'),
  GstState('09', 'Uttar Pradesh'),
  GstState('10', 'Bihar'),
  GstState('11', 'Sikkim'),
  GstState('12', 'Arunachal Pradesh'),
  GstState('13', 'Nagaland'),
  GstState('14', 'Manipur'),
  GstState('15', 'Mizoram'),
  GstState('16', 'Tripura'),
  GstState('17', 'Meghalaya'),
  GstState('18', 'Assam'),
  GstState('19', 'West Bengal'),
  GstState('20', 'Jharkhand'),
  GstState('21', 'Odisha'),
  GstState('22', 'Chhattisgarh'),
  GstState('23', 'Madhya Pradesh'),
  GstState('24', 'Gujarat'),
  GstState('26', 'Dadra & Nagar Haveli and Daman & Diu'),
  GstState('27', 'Maharashtra'),
  GstState('29', 'Karnataka'),
  GstState('30', 'Goa'),
  GstState('31', 'Lakshadweep'),
  GstState('32', 'Kerala'),
  GstState('33', 'Tamil Nadu'),
  GstState('34', 'Puducherry'),
  GstState('35', 'Andaman & Nicobar Islands'),
  GstState('36', 'Telangana'),
  GstState('37', 'Andhra Pradesh'),
  GstState('38', 'Ladakh'),
  GstState('97', 'Other Territory'),
];

/// The state code a GSTIN belongs to — its first two digits — or ''.
String stateCodeFromGstin(String gstin) {
  final trimmed = gstin.trim();
  if (trimmed.length < 2) return '';
  final prefix = trimmed.substring(0, 2);
  return kGstStates.any((s) => s.code == prefix) ? prefix : '';
}

/// Why a chosen state and a typed GSTIN disagree, or null when they agree.
///
/// Worth surfacing rather than trusting one silently: a GSTIN whose prefix is
/// not the selected state means one of the two is a typo, and only the
/// shopkeeper knows which.
String? gstinStateMismatch(String stateCode, String gstin) {
  final fromGstin = stateCodeFromGstin(gstin);
  if (fromGstin.isEmpty || stateCode.isEmpty || fromGstin == stateCode) {
    return null;
  }
  for (final s in kGstStates) {
    if (s.code == fromGstin) {
      return 'This GSTIN starts $fromGstin, which is ${s.name}.';
    }
  }
  return 'This GSTIN starts $fromGstin, which is not a state code.';
}
