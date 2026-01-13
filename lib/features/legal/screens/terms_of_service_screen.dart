import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Terms of Service',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Last Updated: January 5, 2026',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            SizedBox(height: 32),
            _Section(
              title: '1. Acceptance of Terms',
              content:
                  'By accessing, downloading, or using the HangHut mobile application, website, or any related services, collectively the App, you agree to be legally bound by these Terms of Service. If you do not agree to all Terms, you must not access or use the App.\n\nContinued use of the App constitutes ongoing acceptance of these Terms, including any future updates.',
            ),
            _Section(
              title: '2. Eligibility and Age Requirement',
              content:
                  'You must be at least 18 years old, or the age of legal majority in your jurisdiction, whichever is higher, to use the App.\n\nBy using HangHut, you represent and warrant that:\n\n• You meet the minimum legal age requirement\n• You are legally permitted to participate in real-world social activities\n• You are not prohibited by law from using location-based or social services\n\nHangHut does not verify user age or identity and is not responsible for false representations. Any use by underage individuals is strictly unauthorized.',
            ),
            _Section(
              title: '3. Account Registration and Security',
              content:
                  'You are solely responsible for:\n\n• All activity conducted through your account\n• Maintaining the confidentiality of login credentials\n• Any loss or damage resulting from unauthorized access\n\nHangHut is not liable for account misuse, compromised credentials, or unauthorized access, regardless of cause.',
            ),
            _Section(
              title: '4. Nature of the Platform',
              content:
                  'HangHut is a technology platform only. HangHut does not:\n\n• Organize, host, supervise, or endorse events\n• Verify users, events, locations, or activities\n• Provide security, chaperoning, or monitoring services\n\nAll events, meetups, and interactions are user-initiated and user-controlled.',
            ),
            _Section(
              title: '5. User Conduct and Community Rules',
              content:
                  'You agree not to engage in any conduct that is unlawful, harmful, deceptive, or disruptive.\n\nProhibited conduct includes, but is not limited to:\n\n• Harassment, threats, abuse, or intimidation\n• Hate speech, sexual content, or illegal material\n• Stalking, tracking, or exploiting other users\n• Creating fake events or misleading activity listings\n• Impersonation or misrepresentation of identity or intent\n• Using the App for commercial solicitation without authorization\n\nHangHut may remove content or restrict accounts at its sole discretion, without notice or explanation.',
            ),
            _Section(
              title: '6. Real-World Interaction and Safety Disclaimer',
              content:
                  'You acknowledge that:\n\n• HangHut does not control offline behavior\n• Interactions with other users carry inherent risks\n• You assume full responsibility for your safety and decisions\n\nHangHut does not conduct background checks, criminal screenings, or identity verification.\n\nYou agree that any injury, loss, damage, or incident occurring during or after an in-person interaction is your sole responsibility.',
            ),
            _Section(
              title: '7. Location Services and Risk Acknowledgment',
              content:
                  'The App may collect and display real-time or approximate location data.\n\nBy enabling location features, you expressly consent to:\n\n• Collection and processing of location data\n• Display of your location to other users\n• Associated risks of location sharing\n\nYou acknowledge that location-based services may expose you to danger, and HangHut bears no responsibility for misuse, tracking, or harm related to location data.',
            ),
            _Section(
              title: '8. User Content',
              content:
                  'You retain ownership of content you submit. By submitting content, you grant HangHut a worldwide, non-exclusive, perpetual, royalty-free, sublicensable license to use, store, modify, display, distribute, and promote such content in connection with the App.\n\nHangHut may remove or restrict content at any time, for any reason, without liability.',
            ),
            _Section(
              title: '9. No Professional or Safety Advice',
              content:
                  'Any tips, suggestions, or recommendations provided by HangHut are for general informational purposes only and do not constitute professional, legal, medical, or safety advice.\n\nYou remain solely responsible for assessing risks.',
            ),
            _Section(
              title: '10. Disclaimer of Warranties',
              content:
                  'THE APP IS PROVIDED AS IS AND AS AVAILABLE. HANGHUT DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF SAFETY, ACCURACY, RELIABILITY, AND FITNESS FOR A PARTICULAR PURPOSE.\n\nHANGHUT DOES NOT GUARANTEE:\n\n• Event legitimacy\n• User behavior\n• Safety outcomes\n• Availability or uninterrupted service',
            ),
            _Section(
              title: '11. Limitation of Liability',
              content:
                  'TO THE MAXIMUM EXTENT PERMITTED BY LAW, HANGHUT SHALL NOT BE LIABLE FOR ANY DAMAGES OF ANY KIND, INCLUDING PERSONAL INJURY, DEATH, PROPERTY DAMAGE, LOST PROFITS, DATA LOSS, OR EMOTIONAL DISTRESS, ARISING FROM OR RELATED TO:\n\n• Use of the App\n• Offline interactions\n• Events or activities\n• Location sharing\n\nUSE OF THE APP IS ENTIRELY AT YOUR OWN RISK.',
            ),
            _Section(
              title: '12. Indemnification',
              content:
                  'You agree to indemnify and hold harmless HangHut and its affiliates from any claims, liabilities, damages, losses, or expenses arising from:\n\n• Your use of the App\n• Your interactions with other users\n• Your violation of these Terms\n• Any offline incidents involving you',
            ),
            _Section(
              title: '13. Suspension and Termination',
              content:
                  'HangHut may suspend or terminate your account at any time, with or without notice, for any reason, including suspected risk to the community.\n\nNo refunds, compensation, or reinstatement is guaranteed.',
            ),
            _Section(
              title: '14. Modifications to Terms',
              content:
                  'HangHut may update these Terms at any time. Continued use of the App after updates constitutes acceptance of the revised Terms.',
            ),
            _Section(
              title: '15. Governing Law and Jurisdiction',
              content:
                  'These Terms shall be governed by and construed in accordance with the laws of the Philippines, without regard to conflict of law principles. Any disputes shall be resolved exclusively in Philippine courts.',
            ),
            _Section(
              title: '16. Contact',
              content:
                  'Questions or concerns may be directed to support@hanghut.com',
            ),
            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String content;

  const _Section({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
