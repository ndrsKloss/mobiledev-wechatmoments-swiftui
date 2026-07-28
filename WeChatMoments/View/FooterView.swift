//
//  FooterView.swift
//  WeChatMoments
//
//  Created by Wole Solana on 3/12/24.
//

import SwiftUI

/// The hairline rule between two tweet cells (FR-TWEET-008).
///
/// It used to draw itself inside a `GeometryReader` nested in a `VStack`, purely to learn a width
/// it could have taken from its parent — and a `GeometryReader` claims all the height offered to
/// it, so the "hairline" reserved an arbitrary block of space and offset itself by -0.5 to
/// compensate. Asking the layout system for full width instead is both correct and adaptive
/// (NFR-LAYOUT-001).
struct FooterView: View {
    var body: some View {
        Rectangle()
            .fill(Color.commentsBackgroudColor)
            .frame(maxWidth: .infinity)
            .frame(height: Constants.SEPARATOR_HEIGHT)
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("above")
        FooterView()
        Text("below")
    }
}
