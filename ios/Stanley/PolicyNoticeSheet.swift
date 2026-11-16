import SwiftUI

/// The sheet that says the Privacy Policy changed (build 70; when it comes
/// up and what it says are `PolicyNotice`'s). Set like the policy itself:
/// plain system type on the system's page, no paper and no hand, since it's
/// the policy speaking. It can't be swiped away; the one button
/// acknowledges it, and the whole policy is a tap away.
struct PolicyNoticeSheet: View {
    let unread: [PolicyNotice.Revision]
    let acknowledge: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Effective \(Legal.privacyEffective)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                    Text("Here's what changed, in short. The policy says it in full.")
                        .font(.body)
                        .padding(.bottom, 8)
                    ForEach(unread, id: \.day) { revision in
                        VStack(alignment: .leading, spacing: 10) {
                            if unread.count > 1 {
                                Text(revision.title)
                                    .font(.headline)
                            }
                            ForEach(revision.changes, id: \.self) { change in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(change)
                                }
                            }
                        }
                        .padding(.top, 20)
                    }
                    NavigationLink {
                        LegalDocumentView(title: "Privacy Policy", sections: Legal.privacy, effective: Legal.privacyEffective)
                    } label: {
                        Label("Read the Privacy Policy", systemImage: "doc.text")
                    }
                    .tint(.blue)
                    .padding(.top, 28)
                }
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                WideButton(title: "Got It", action: acknowledge)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .systemBackground))
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Privacy Policy Updated")
            .navigationBarTitleDisplayMode(.large)
        }
        .interactiveDismissDisabled()
    }
}
