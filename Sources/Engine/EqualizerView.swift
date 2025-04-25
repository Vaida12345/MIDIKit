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
    
    let parameters: EqualizerParameters
    
    
    public var body: some View {
        @Bindable var parameters = parameters
        
        HStack {
            VStack {
                EqualizerSlider(value: $parameters.globalGain)
                    .frame(width: 30)
                    .background {
                        EqualizerBackground()
                    }
                    .onChange(of: parameters.globalGain) { oldValue, newValue in
                        UserDefaults.standard.set(newValue, forKey: "EqualizerParameters.globalGain")
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
                                .onChange(of: band.wrappedValue.gain) { oldValue, newValue in
                                    UserDefaults.standard.set(newValue, forKey: "EqualizerParameters.bands.\(band.wrappedValue.description)")
                                }
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
    
    public init(parameters: EqualizerParameters) {
        self.parameters = parameters
    }
}


#Preview {
    EqualizerView(parameters: .init())
}
#endif
