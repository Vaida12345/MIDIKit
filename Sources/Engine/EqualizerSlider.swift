//
//  EqualizerSlider.swift
//  MIDIKit
//
//  Created by Vaida on 4/25/25.
//

import Essentials
import SwiftUI
import CoreFoundation


struct EqualizerSlider: View {
    
    @Binding var value: Float
    
    @State private var location: Double = 0
    
    private let range: ClosedRange<Float> = -12 ... 12
    
    private let scale: Float = 24
    
    private var radius: Double {
        4
    }
    
    private var diameter: Double {
        radius * 2
    }
    
    private var gesture: some Gesture {
        DragGesture()
            .onChanged { value in
                location = value.location.y
            }
    }
    
    private var normalized: Float {
        get {
            (-value - range.lowerBound) / scale
        }
        nonmutating set {
            value = -(newValue * scale + range.lowerBound)
        }
    }
    
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    context.fill(
                        Path(
                            roundedRect: CGRect(origin: CGPoint(x: geometry.size.width / 2 - radius / 2, y: 0),
                                                size: CGSize(width: radius, height: size.height)),
                            cornerRadius: radius / 2),
                        with: .color(Color.sliderProgressBarColor))
                    
                    let y = Double(normalized) * (geometry.size.height - diameter) + radius
                    let height = abs(y - geometry.size.height / 2)
                    let rect = CGRect(x: geometry.size.width / 2 - radius / 2,
                                      y: min(y, geometry.size.height / 2),
                                      width: radius,
                                      height: height)
                    context.fill(Path(rect), with: .color(.accentColor))
                }
                
                Capsule()
                    .fill(Color.handleColor)
                    .frame(width: diameter * 3, height: diameter)
                    .shadow(radius: 1)
                    .padding()
                    .position(x: geometry.size.width / 2, y: Double(normalized) * (geometry.size.height - diameter) + radius)
                    .contentShape(Rectangle())
                    .gesture(gesture)
            }
            .onChange(of: location) { oldValue, newValue in
                normalized = Float(clamp((newValue - radius) / (geometry.size.height - diameter), min: 0, max: 1))
            }
        }
        .frame(width: diameter * 4)
    }
}


private extension Color {
    
    static var sliderProgressBarColor: Color {
        Color(white: 22 / 255)
    }
    
    static var handleColor: Color {
        Color(white: 150 / 255)
    }
    
}


#Preview {
    @Previewable @State var value: Float = 0
    
    EqualizerSlider(value: $value)
        .border(.red)
        .frame(width: 30, height: 200)
        .padding(.vertical)
}
