import SwiftUI

/// The open-source code inside the app, with the notices its licenses ask
/// to travel with it (the production audit, November 2026). Sentry's SDK is
/// the only third-party code compiled into Stanley for iPhone; the server's
/// libraries run on Stanley's own machine and aren't distributed. The fonts
/// (Noteworthy, New York, SF) are Apple's own, part of iOS.
struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Stanley is built with this open-source software. Thank you to the people who wrote it.")
                    .font(.callout)
                ForEach(Self.notices, id: \.name) { notice in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(notice.name).font(.headline)
                        Text(notice.license).smallCaps(11)
                        Text(notice.text)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atmosphereWash()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    struct Notice {
        let name: String
        let license: String
        let text: String
    }

    static let notices: [Notice] = [
        Notice(
            name: "Sentry Cocoa SDK",
            license: "MIT License · github.com/getsentry/sentry-cocoa",
            text: """
            Copyright (c) 2015 Sentry

            Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
            """
        ),
    ]
}
