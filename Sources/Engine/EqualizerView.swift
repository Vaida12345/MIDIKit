//
//  EqualizerView.swift
//  MIDIKit
//
//  Created by Vaida on 4/25/25.
//

#if os(macOS)
import SwiftUI
import ViewCollection


public struct EqualizerView: View {
    
    @Binding public var parameters: EqualizerParameters
    
    
    public var body: some View {
        HStack {
            VStack {
                EqualizerSlider(value: $parameters.globalGain)
                    .frame(width: 30)
                    .background {
                        EqualizerBackground()
                    }
                
                Text("Global")
            }
            
            VStack {
                Text("+12 dB")
                Spacer()
                Text("0 dB")
                Spacer()
                Text("-12 dB")
                
                Text("")
                    .hidden()
            }
            .foregroundStyle(.secondary)
            
            VStack {
                ZStack {
                    EqualizerBackground()
                    
                    HStack {
                        ForEach($parameters.bands) { band in
                            EqualizerSlider(value: band.gain)
                                .frame(width: 30)
                        }
                    }
                }
                
                HStack {
                    ForEach(parameters.bands) { band in
                        Text(band.description)
                            .frame(width: 30)
                    }
                }
            }
        }
        .frame(width: 450, height: 200)
        .padding()
    }
    
    public init(parameters: Binding<EqualizerParameters>) {
        self._parameters = parameters
    }
}


#Preview {
    EqualizerView(parameters: .constant(.init()))
}
#endif
