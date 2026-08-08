/**
 * Web-only strings, in English, Hindi and Gujarati.
 *
 * Everything in messages.generated.ts comes from the mobile app's reviewed
 * translations. These are strings that exist only on the web, so there was no
 * existing translation to reuse and I have proposed one.
 *
 * Reviewed by a native speaker on 8 August 2026 and accepted as written. Keep
 * them in this one file so a future correction is a single pass rather than a
 * hunt through components.
 *
 * Where a term is genuinely used in English by Indian shopkeepers (GST, GSTIN,
 * SKU, UPI, POS, PIN, CSV) it is left in English on purpose rather than
 * translated into something nobody says at a counter.
 *
 * One string was flagged during that review and kept anyway: `webConfirmAdjustment`
 * renders as "ફેરફાર ખાતરી કરો", where the genitive ("ફેરફારની") looked to me
 * like it might be required. The reviewer read it and did not change it, so it
 * stands — noted here only so nobody re-raises it as a new finding.
 */

export const WEB_MESSAGES = {
  en: {
    // --- sign in -------------------------------------------------------
    webSignIn: "Sign in",
    webSignInCloud: "Sign in with Cloud Account",
    webEmail: "Email",
    webEmailAddress: "Email Address",
    webPassword: "Password",
    webCreateShop: "Create a shop",
    webJoinWithCode: "Join with a code",
    webJoinShop: "JOIN SHOP",
    webInviteCode: "Invite code",
    webInviteHint: "Enter the invite code from your email to join your team.",
    webBackToSignIn: "Back to sign in",
    webStaffPinLogin: "Switch to Staff PIN Login",
    webPinHint: "Enter your PIN to unlock the POS terminal.",
    webBusinessName: "Business name",
    webMobileOptional: "Mobile (optional)",
    webGstinOptional: "GSTIN (optional)",

    // --- till ----------------------------------------------------------
    webCurrentCart: "Current Cart",
    webCartEmpty: "Cart is currently empty",
    webClearCart: "Clear Cart",
    webCharge: "CHARGE",
    webCheckoutPayment: "Checkout & Payment",
    webConfirmPrint: "CONFIRM & PRINT RECEIPT",
    webGrandTotal: "Grand Total",
    webGiveCredit: "Give Credit (Udhaar)",
    webAttachCustomer: "Attach Khata / Customer Account",
    webNoProductsMatch: "No products found matching your search filters.",
    webClear: "CLEAR",

    // --- stock ---------------------------------------------------------
    webInventoryCatalog: "Inventory & Catalog",
    webAddProduct: "Add Product",
    webEditProduct: "Edit product",
    webAdjustStock: "Adjust Stock",
    webAdjustmentType: "Adjustment Type",
    webAdjustmentNote: "Adjustment Reason / Note",
    webConfirmAdjustment: "Confirm Adjustment",
    webCurrentStockUnits: "Current Stock (Units)",
    webCostPrice: "Cost Price",
    webGstSlab: "GST Slab",
    webBarcode: "Barcode",
    webLowStockOnly: "Low Stock Only",
    webExportCsv: "Export CSV",

    // --- customers and khata -------------------------------------------
    webAddCustomer: "Add Customer",
    webActiveUdhaar: "Active Udhaar Accounts",
    webMoneyOutUdhaar: "Money out on udhaar",
    webLedgerTimeline: "Ledger History Timeline",
    webNoLedgerYet: "No ledger transactions recorded for this customer yet.",
    webNoCustomersFound: "No customers found.",
    webNoMobileNumber: "No mobile number",
    webLifetimeSpend: "Lifetime Business Spend",
    webCustomerNotes: "Customer Notes",

    // --- shared --------------------------------------------------------
    webActions: "Actions",
    webCategory: "Category",
    webOptional: "optional",
  },

  hi: {
    webSignIn: "साइन इन करें",
    webSignInCloud: "क्लाउड खाते से साइन इन करें",
    webEmail: "ईमेल",
    webEmailAddress: "ईमेल पता",
    webPassword: "पासवर्ड",
    webCreateShop: "नई दुकान बनाएँ",
    webJoinWithCode: "कोड से जुड़ें",
    webJoinShop: "दुकान से जुड़ें",
    webInviteCode: "इनवाइट कोड",
    webInviteHint: "अपनी टीम से जुड़ने के लिए ईमेल में मिला इनवाइट कोड डालें।",
    webBackToSignIn: "वापस साइन इन पर",
    webStaffPinLogin: "स्टाफ PIN लॉगिन पर जाएँ",
    webPinHint: "बिलिंग खोलने के लिए अपना PIN डालें।",
    webBusinessName: "दुकान का नाम",
    webMobileOptional: "मोबाइल (वैकल्पिक)",
    webGstinOptional: "GSTIN (वैकल्पिक)",

    webCurrentCart: "मौजूदा कार्ट",
    webCartEmpty: "कार्ट खाली है",
    webClearCart: "कार्ट खाली करें",
    webCharge: "पैसे लें",
    webCheckoutPayment: "भुगतान",
    webConfirmPrint: "पक्का करें और रसीद छापें",
    webGrandTotal: "कुल रकम",
    webGiveCredit: "उधार दें",
    webAttachCustomer: "खाता / ग्राहक जोड़ें",
    webNoProductsMatch: "आपकी खोज से मेल खाता कोई सामान नहीं मिला।",
    webClear: "मिटाएँ",

    webInventoryCatalog: "स्टॉक और सामान की सूची",
    webAddProduct: "नया सामान जोड़ें",
    webEditProduct: "सामान बदलें",
    webAdjustStock: "स्टॉक ठीक करें",
    webAdjustmentType: "बदलाव का प्रकार",
    webAdjustmentNote: "बदलाव का कारण / टिप्पणी",
    webConfirmAdjustment: "बदलाव पक्का करें",
    webCurrentStockUnits: "मौजूदा स्टॉक (नग)",
    webCostPrice: "खरीद भाव",
    webGstSlab: "GST दर",
    webBarcode: "बारकोड",
    webLowStockOnly: "सिर्फ़ कम स्टॉक",
    webExportCsv: "CSV निकालें",

    webAddCustomer: "ग्राहक जोड़ें",
    webActiveUdhaar: "चालू उधार खाते",
    webMoneyOutUdhaar: "उधार में गया पैसा",
    webLedgerTimeline: "खाता इतिहास",
    webNoLedgerYet: "इस ग्राहक का कोई खाता लेन-देन दर्ज नहीं है।",
    webNoCustomersFound: "कोई ग्राहक नहीं मिला।",
    webNoMobileNumber: "मोबाइल नंबर नहीं है",
    webLifetimeSpend: "कुल खरीदारी",
    webCustomerNotes: "ग्राहक के बारे में टिप्पणी",

    webActions: "कार्रवाई",
    webCategory: "श्रेणी",
    webOptional: "वैकल्पिक",
  },

  gu: {
    webSignIn: "સાઇન ઇન કરો",
    webSignInCloud: "ક્લાઉડ ખાતાથી સાઇન ઇન કરો",
    webEmail: "ઈમેલ",
    webEmailAddress: "ઈમેલ સરનામું",
    webPassword: "પાસવર્ડ",
    webCreateShop: "નવી દુકાન બનાવો",
    webJoinWithCode: "કોડથી જોડાઓ",
    webJoinShop: "દુકાન સાથે જોડાઓ",
    webInviteCode: "ઇન્વાઇટ કોડ",
    webInviteHint: "તમારી ટીમ સાથે જોડાવા ઈમેલમાં મળેલો ઇન્વાઇટ કોડ નાખો.",
    webBackToSignIn: "પાછા સાઇન ઇન પર",
    webStaffPinLogin: "સ્ટાફ PIN લોગિન પર જાઓ",
    webPinHint: "બિલિંગ ખોલવા તમારો PIN નાખો.",
    webBusinessName: "દુકાનનું નામ",
    webMobileOptional: "મોબાઇલ (વૈકલ્પિક)",
    webGstinOptional: "GSTIN (વૈકલ્પિક)",

    webCurrentCart: "હાલનું કાર્ટ",
    webCartEmpty: "કાર્ટ ખાલી છે",
    webClearCart: "કાર્ટ ખાલી કરો",
    webCharge: "પૈસા લો",
    webCheckoutPayment: "ચુકવણી",
    webConfirmPrint: "ખાતરી કરો અને રસીદ છાપો",
    webGrandTotal: "કુલ રકમ",
    webGiveCredit: "ઉધાર આપો",
    webAttachCustomer: "ખાતું / ગ્રાહક જોડો",
    webNoProductsMatch: "તમારી શોધ સાથે મેળ ખાતી કોઈ વસ્તુ મળી નથી.",
    webClear: "ભૂંસો",

    webInventoryCatalog: "સ્ટોક અને વસ્તુઓની યાદી",
    webAddProduct: "નવી વસ્તુ ઉમેરો",
    webEditProduct: "વસ્તુ બદલો",
    webAdjustStock: "સ્ટોક સુધારો",
    webAdjustmentType: "ફેરફારનો પ્રકાર",
    webAdjustmentNote: "ફેરફારનું કારણ / નોંધ",
    webConfirmAdjustment: "ફેરફાર ખાતરી કરો",
    webCurrentStockUnits: "હાલનો સ્ટોક (નંગ)",
    webCostPrice: "ખરીદ ભાવ",
    webGstSlab: "GST દર",
    webBarcode: "બારકોડ",
    webLowStockOnly: "ફક્ત ઓછો સ્ટોક",
    webExportCsv: "CSV કાઢો",

    webAddCustomer: "ગ્રાહક ઉમેરો",
    webActiveUdhaar: "ચાલુ ઉધાર ખાતાં",
    webMoneyOutUdhaar: "ઉધારમાં ગયેલા પૈસા",
    webLedgerTimeline: "ખાતાનો ઇતિહાસ",
    webNoLedgerYet: "આ ગ્રાહકનો કોઈ ખાતા વ્યવહાર નોંધાયેલ નથી.",
    webNoCustomersFound: "કોઈ ગ્રાહક મળ્યો નથી.",
    webNoMobileNumber: "મોબાઇલ નંબર નથી",
    webLifetimeSpend: "કુલ ખરીદી",
    webCustomerNotes: "ગ્રાહક વિશે નોંધ",

    webActions: "ક્રિયાઓ",
    webCategory: "શ્રેણી",
    webOptional: "વૈકલ્પિક",
  },
} as const;

export type WebMessageKey = keyof (typeof WEB_MESSAGES)["en"];
