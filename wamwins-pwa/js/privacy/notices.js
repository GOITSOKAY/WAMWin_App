// Legal notices and consent texts, versioned. A consent record stores the document code + version + a hash of
// the exact text shown, so it is always provable what a person agreed to. Material changes = new version =
// people are asked again. Same texts in the Flutter app (lib/privacy/notices.dart): CLIENT_CONFORMANCE rule P1.
//
// DRAFT FOR LEGAL REVIEW. Items in [brackets] must be completed by WAM Digital before public launch.
export const LEGAL = {
  operator: 'WAM Digital',
  product: 'WAMWins',
  contactEmail: '[privacy contact email]',
  postalAddress: '[mailing address]',
  effective: 'November 16, 2026',
  version: '2026-11-16',
};

const C = LEGAL;
// Each section: { h: heading, p: [paragraphs], list: [bullets] }
export const DOCS = {
  PRIVACY_NOTICE: {
    title: 'Privacy Notice', version: C.version,
    sections: [
      { p: [`Effective ${C.effective}. This notice explains how ${C.operator} (“we”) collects, uses, shares and protects personal information in ${C.product}, and the choices and rights you have.`] },
      { h: 'Information we collect', list: [
        'Account details: your name, email address and a protected one-way code of your password (never the password itself).',
        'Household details: the household name, the people you add (names, relationship, age group) and who does the cooking.',
        'Consumer health data, only with your consent: allergies, intolerances, dietary requirements, health-related food goals, foods to avoid or prioritize, meal preferences and meal history. See the Consumer Health Data Privacy Policy.',
        'Kitchen details: kitchens, storage, appliances, kitchenware and the food you enter.',
        'Photos you choose to add as reference pictures. They are stored, never analyzed, in WAMWins Basic.',
        'Voice commands, only in plans that include them and only after you turn them on. See “Voice commands” below.',
        'Basic technical information needed to run the app safely, such as the app version and error reports.' ] },
      { h: 'How we use it', list: [
        'To run the features you use: setting up your household, inventory, and matching meals to your family’s saved food needs.',
        'To keep accounts and data secure, prevent misuse and fix problems.',
        'To meet legal obligations and respond to your requests.' ],
        p: ['We do not sell personal information. We do not use your health data for advertising, and we do not share personal information for cross-context behavioral advertising. We do not use your health data to train artificial intelligence models.'] },
      { h: 'Where it is stored', p: [
        'Your information is stored on your device. When you use online features such as cloud backup or signing in on other devices, it is also stored in encrypted form on servers in North America.'] },
      { h: 'Who can see it', list: [
        'You, and the people you choose. Health details are visible only to the person they describe, the parent or guardian who manages a child’s profile, and anyone you give access to for the time you choose. You can end access at any time.',
        'Service providers that host and secure our systems or send account emails, under contracts that allow them to use the information only to provide those services to us.',
        'Others when the law requires it, for example a valid court order, or to protect someone’s safety. If we can, we will tell you first.',
        'A buyer or successor if our business is sold or merged, under the same promises; we will tell you before your information becomes subject to a different policy.' ] },
      { h: 'Your rights and choices', list: [
        'See and download a copy of your information (Privacy & sharing → Download a copy).',
        'Correct information in the app, or ask us to correct it.',
        'Delete health details, a family member’s profile, or your whole account and household.',
        'Withdraw a consent at any time. Withdrawing does not affect use before it, and other features keep working.',
        'Ask which people and companies received your consumer health data.',
        'Appeal if we decline a request. You can also contact your state attorney general.' ],
        p: [`To make a request, use Privacy & sharing in the app or email ${C.contactEmail}. We respond within 45 days and may verify your identity first. You may use an authorized agent. We will not treat you differently for using your rights.`] },
      { h: 'How long we keep it', list: [
        'Health details: while your consent is active. Deleted within 30 days after you withdraw consent or ask us to delete them.',
        'Account and household information: while your account is open. Deleted within 30 days after you delete your account.',
        'Meal and matching history: 24 months, then deleted automatically.',
        'Encrypted backups: replaced or deleted within 35 days.',
        'Consent records and access history: 6 years, to prove what was agreed and who viewed health details. They contain no health details.',
        'Voice: no audio is kept. Spoken words are turned into text for the command and then discarded.' ] },
      { h: 'Security', p: ['We use safeguards such as encryption in transit, protected password storage, household-level access controls, access logs and regular reviews. No system is completely secure. If a breach affects your health data, we will notify you and the authorities without unreasonable delay and within the time the law requires (no later than 60 days after discovery).'] },
      { h: 'Children', p: [`${C.product} is not directed to children, and accounts are for adults 18 and older. A parent or legal guardian may add a child’s profile and food needs; we ask for the parent’s consent first. Parents can review, change or delete a child’s information, and withdraw consent, at any time. We do not share children’s information with third parties for advertising or any purpose that is not needed to run the service.`] },
      { h: 'HIPAA', p: [`${C.product} is a consumer wellness app. ${C.operator} is not a health care provider, health plan or health care clearinghouse and does not act for one, so the information you enter is not covered by HIPAA. We still protect your health information with safeguards modeled on the HIPAA Security Rule, and federal and state consumer health privacy laws apply. If we ever offer features for health care providers, those features will operate under a business associate agreement.`] },
      { h: 'Voice commands', p: ['Voice commands are an optional feature in some plans. They are off until you turn them on and agree. When your device supports it, speech is recognized on the device. Otherwise your device’s speech service turns the audio into text; that service is provided by your browser or phone maker under their own privacy terms. WAMWins does not keep recordings, does not create voiceprints and does not identify people by their voice.'] },
      { h: 'State privacy rights', p: ['Residents of California, Washington, Nevada, Colorado, Connecticut, Virginia, Texas, Oregon and other states with consumer privacy laws have the rights described above. California residents: we collect the categories listed in this notice, including sensitive personal information (health), only to provide the service you request; we do not sell or share it. Washington and Nevada residents: see the Consumer Health Data Privacy Policy.'] },
      { h: 'Changes', p: ['If we change this notice in a way that matters, we will tell you in the app before the change applies and ask for your consent again where the law requires.'] },
      { h: 'Contact', p: [`${C.operator}, ${C.postalAddress}. Email: ${C.contactEmail}.`] },
    ],
  },
  CONSUMER_HEALTH_DATA_POLICY: {
    title: 'Consumer Health Data Privacy Policy', version: C.version,
    sections: [
      { p: [`Effective ${C.effective}. This policy applies to consumer health data under the Washington My Health My Data Act, Nevada law and similar state laws.`] },
      { h: 'Consumer health data we collect', list: ['Allergies and intolerances', 'Dietary requirements (for example vegetarian, gluten-free, halal)', 'Health-related food goals (for example lower sodium, higher protein)', 'Foods to avoid or prioritize, per meal', 'Meal preferences and the meals you record'] },
      { h: 'Why we collect and use it', p: ['Only to match meals and food to the needs you enter, and to show those needs to the people you choose. We do not use it for advertising, we do not sell it, and we do not infer medical conditions from it.'] },
      { h: 'Where it comes from', p: ['From you, and from people you allow to edit a profile. A parent or guardian enters a child’s information.'] },
      { h: 'Who receives it', list: [
        'People you give access to, for the categories and time you choose.',
        'Service providers (processors) that host and secure our systems, only to provide the service to us. Categories: cloud hosting, data backup, security monitoring.',
        'No affiliates and no data brokers receive it.' ] },
      { h: 'Your choices', list: [
        'We ask for your consent before we collect health data, and separately before it is shared with anyone you choose.',
        'Withdraw consent, see or delete the data, and ask for the list of people and companies that received it, in Privacy & sharing or by email.',
        'We never sell consumer health data. Selling it would require your separate signed authorization, which we do not request.',
        'We do not use location to geofence health care facilities.' ],
        p: [`Requests: Privacy & sharing in the app, or ${C.contactEmail}. We respond within 45 days. You may appeal a refusal by replying to our answer; if you are not satisfied, you may contact your state attorney general.`] },
    ],
  },
  TERMS: {
    title: 'Terms of Use', version: C.version,
    sections: [
      { p: [`Effective ${C.effective}. These terms are an agreement between you and ${C.operator} about using ${C.product}.`] },
      { h: 'Who can use WAMWins', p: ['You must be 18 or older to create an account. You may add profiles for your family, including children, if you are their parent or legal guardian or have their permission.'] },
      { h: 'Not medical advice', list: [
        'WAMWins is a general wellness and household tool. It does not diagnose, treat, cure or prevent any disease and is not a medical device.',
        'Meal suggestions depend on the information you enter and on recipe and product data, which can be incomplete. Always read ingredient labels and confirm suitability, especially for allergies.',
        'Talk to a doctor or registered dietitian about medical or nutrition needs. In an allergic emergency, call 911.' ] },
      { h: 'Your information', p: ['You own what you enter. You give us permission to store and process it only to provide WAMWins to you, as described in the Privacy Notice. You are responsible for having permission to enter information about other people.'] },
      { h: 'Using WAMWins responsibly', list: ['Keep your password private and tell us about any unauthorized use.', 'Do not misuse the service, try to access other households’ data, or interfere with its security.'] },
      { h: 'Plans and features', p: ['WAMWins Basic is free. Some features, such as voice commands, are available only in other plans. Platform protections (privacy controls, consent management, data export, account deletion and backup) are included in every plan.'] },
      { h: 'Changes and ending', p: ['We may update these terms and will tell you in the app before material changes apply. You can stop using WAMWins and delete your account at any time.'] },
      { h: 'Disclaimers', p: ['WAMWins is provided “as is”. To the extent the law allows, WAM Digital is not liable for indirect or consequential damages. Nothing in these terms limits rights you have under consumer protection laws that cannot be waived.'] },
      { h: 'Contact', p: [`${C.operator}, ${C.postalAddress}. Email: ${C.contactEmail}. Governing law: [state to be confirmed by WAM Digital].`] },
    ],
  },
};

// Consent types (stored in consent_record.consent_type). Each names the document it relies on.
export const CONSENT = {
  TERMS: { doc: 'TERMS', version: C.version },
  PRIVACY_POLICY: { doc: 'PRIVACY_NOTICE', version: C.version },
  AGE_18_PLUS: { doc: 'TERMS', version: C.version },
  HEALTH_DATA_PROCESSING: {
    doc: 'CONSUMER_HEALTH_DATA_POLICY', version: C.version,
    title: 'Consent to collect and use health details',
    lead: 'WAMWins can use your household’s allergies, intolerances, diets and health-related food goals to match meals to everyone’s needs. This is optional.',
    list: [
      'What: allergies, intolerances, dietary requirements, health-related food goals, foods to avoid or prioritize, and meal preferences you enter.',
      'Why: only to match meals and food to these needs. Never for advertising, never sold, never used to train AI models.',
      'Where: on this device, and encrypted in North America if you use online backup or sign in on other devices.',
      'Who can see it: the person it describes, the parent or guardian managing a child, and only the people you choose, for the time you choose.',
      'How long: while this consent is on. Deleted within 30 days after you turn it off or ask us to delete it.',
      'Your choice: you can say no and still use every other feature. You can withdraw any time in Privacy & sharing.' ],
    check: 'I agree that WAMWins may collect and use these health details for meal matching, as described above and in the Consumer Health Data Privacy Policy.',
    agree: 'I agree', decline: 'Not now',
  },
  CHILD_PROFILE: {
    doc: 'PRIVACY_NOTICE', version: C.version,
    title: 'Parent or guardian consent',
    lead: 'You are adding food and health details for a child or teen. We need a parent’s or legal guardian’s consent first.',
    list: [
      'WAMWins uses the child’s details only for meal matching in your household.',
      'They are never used for advertising and never shared with third parties except service providers that run WAMWins for us.',
      'You can review, change or delete the child’s information, and withdraw this consent, at any time in Privacy & sharing.',
      'The child’s profile is managed by you; children do not use WAMWins accounts.' ],
    check: 'I am this child’s parent or legal guardian and I consent to WAMWins collecting and using these details as described.',
    agree: 'I consent', decline: 'Cancel',
  },
  ADULT_ON_BEHALF: {
    doc: 'PRIVACY_NOTICE', version: C.version,
    title: 'Adding another adult’s health details',
    lead: 'Health details belong to the person they describe.',
    list: [
      'Add another adult’s details only with their permission, or if you are legally authorized to act for them.',
      'They can ask to see, correct or delete their details, and can manage them with their own account later.' ],
    check: 'I have this person’s permission, or I am authorized to act for them.',
    agree: 'Confirm', decline: 'Cancel',
  },
  HEALTH_DATA_SHARING: {
    doc: 'CONSUMER_HEALTH_DATA_POLICY', version: C.version,
    title: 'Consent to share health details',
    lead: 'You are giving someone access to health details. This is a separate consent from collecting them.',
    check: 'I consent to sharing these details with this person, for the time shown. I can end access at any time.',
    agree: 'Give access', decline: 'Cancel',
  },
  MEDIA_PROCESSING: {
    doc: 'PRIVACY_NOTICE', version: C.version,
    title: 'Reference photos',
    lead: 'Photos help you remember where things are. They are stored with your household and are never analyzed in WAMWins Basic.',
    list: ['Avoid photographing people, documents or anything private.', 'Only household members can see them, and you can delete them at any time.'],
    check: 'I understand how reference photos are stored.',
    agree: 'Continue', decline: 'Cancel',
  },
  VOICE_COMMANDS: {
    doc: 'PRIVACY_NOTICE', version: C.version,
    title: 'Turn on voice commands',
    lead: 'Say things like “open inventory”, “what can we cook” or “add 2 pounds of chicken breast”.',
    list: [
      'The microphone listens only after you tap the microphone button, and stops after one command.',
      'Speech is recognized on your device when it supports it. Otherwise your browser’s or phone maker’s speech service converts it to text under their privacy terms.',
      'WAMWins does not keep recordings, does not create voiceprints and does not identify people by voice. The text is used for the command and then discarded.',
      'Anything that changes your data is shown to you to confirm first.',
      'Turn voice commands off any time in Settings.' ],
    check: 'I agree to use voice commands as described.',
    agree: 'Turn on', decline: 'Not now',
  },
};

// Access categories a person can share. Same codes in Postgres (privacy.access_grant.categories) and Flutter.
export const ACCESS_CATEGORIES = [
  { code: 'ALLERGIES', name: 'Allergies and intolerances' },
  { code: 'DIETS', name: 'Dietary requirements' },
  { code: 'HEALTH_GOALS', name: 'Health-related food goals' },
  { code: 'FOOD_RULES', name: 'Foods to avoid or prioritize' },
  { code: 'MEAL_PREFERENCES', name: 'Meal preferences' },
  { code: 'MEAL_HISTORY', name: 'Meal history' },
];
export const ACCESS_DURATIONS = [
  { code: 'P1D', name: '24 hours', days: 1 }, { code: 'P7D', name: '7 days', days: 7 }, { code: 'P30D', name: '30 days', days: 30 },
  { code: 'P90D', name: '90 days', days: 90 }, { code: 'CUSTOM', name: 'Choose dates' }, { code: 'NONE', name: 'Until I end it' },
];

export async function textHash(parts) {
  const data = new TextEncoder().encode(JSON.stringify(parts));
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', data))].map(b => b.toString(16).padStart(2, '0')).join('');
}
