import SwiftUI

enum BowlingVenues {
  static let all: [Venue] = [
    Venue(
      id: "neon-lanes", gameID: "bowling", name: "Neon Lanes",
      tagline: "Synth-soaked starter alley.", unlockAt: 0
    ) {
      NeonLanesBG()
    },
    Venue(
      id: "tropical-island", gameID: "bowling", name: "Tropical Island",
      tagline: "Bowling at low tide.", unlockAt: 100,
      modifier: VenueModifier(
        flavorLine: "Soft sand under the lane — gentle rolls go further."
      )
    ) {
      TropicalIslandBG()
    },
    Venue(
      id: "sunset-strip", gameID: "bowling", name: "Sunset Strip",
      tagline: "Palm trees and magenta skies.", unlockAt: 200,
      modifier: VenueModifier(
        flavorLine: "Warm lane oil — weak rolls still knock pins.",
        effect: .stickyLane
      )
    ) {
      SunsetStripBG()
    },
    Venue(
      id: "desert-dunes", gameID: "bowling", name: "Desert Dunes",
      tagline: "Pyramids on the horizon.", unlockAt: 350,
      modifier: VenueModifier(
        flavorLine: "Hot wind shifts your line — aim true."
      )
    ) {
      DesertDunesBG()
    },
    Venue(
      id: "jungle-temple", gameID: "bowling", name: "Jungle Temple",
      tagline: "Mossy stones, watching eyes.", unlockAt: 500,
      modifier: VenueModifier(
        scoreMultiplier: 1.5,
        flavorLine: "Sacred ground rewards every pin 1.5×."
      )
    ) {
      JungleTempleBG()
    },
    Venue(
      id: "dragon-shrine", gameID: "bowling", name: "Dragon Shrine",
      tagline: "Holy ground. Roll with reverence.", unlockAt: 750,
      modifier: VenueModifier(
        scoreMultiplier: 2.0,
        difficultyMultiplier: 1.3,
        flavorLine: "Sacred lane. Double points, unforgiving pins."
      )
    ) {
      DragonShrineBG()
    },
  ]
}

// MARK: - Shared scenery primitives

/// A simple star field of small dots for night-sky venues.
private struct Stars: View {
  let count: Int
  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      ForEach(0..<count, id: \.self) { i in
        // Deterministic positions so they don't twinkle every render.
        let x = CGFloat((i * 37) % Int(max(w, 1)))
        let y = CGFloat((i * 61) % Int(max(h * 0.6, 1)))
        Circle()
          .fill(Color.white.opacity(Double((i % 5) + 2) / 8))
          .frame(width: 2, height: 2)
          .position(x: x, y: y)
      }
    }
  }
}

/// Layered triangular mountain silhouette band (for distance + depth).
private struct MountainSilhouettes: View {
  let color: Color
  let baseY: CGFloat
  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      Path { p in
        p.move(to: CGPoint(x: 0, y: h * baseY))
        p.addLine(to: CGPoint(x: w * 0.18, y: h * (baseY - 0.18)))
        p.addLine(to: CGPoint(x: w * 0.32, y: h * (baseY - 0.05)))
        p.addLine(to: CGPoint(x: w * 0.48, y: h * (baseY - 0.22)))
        p.addLine(to: CGPoint(x: w * 0.62, y: h * (baseY - 0.08)))
        p.addLine(to: CGPoint(x: w * 0.78, y: h * (baseY - 0.16)))
        p.addLine(to: CGPoint(x: w, y: h * (baseY - 0.04)))
        p.addLine(to: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: 0, y: h))
        p.closeSubpath()
      }
      .fill(color)
    }
  }
}

// MARK: - Neon Lanes

private struct NeonLanesBG: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.05, green: 0.02, blue: 0.18),
          Color(red: 0.18, green: 0.04, blue: 0.32),
          Color(red: 0.30, green: 0.06, blue: 0.45),
        ],
        startPoint: .top, endPoint: .bottom
      )
      // Distant skyline silhouette.
      MountainSilhouettes(color: Color(red: 0.08, green: 0.02, blue: 0.22), baseY: 0.55)
      // Neon glow strips on the horizon.
      VStack(spacing: 4) {
        Spacer()
        Rectangle()
          .fill(Color(red: 1.0, green: 0.25, blue: 0.85))
          .frame(height: 2)
          .blur(radius: 2)
        Rectangle()
          .fill(Color(red: 0.3, green: 0.85, blue: 1.0))
          .frame(height: 1)
          .blur(radius: 1.5)
          .opacity(0.7)
        Spacer().frame(height: 80)
      }
      // Foreground neon spotlights converging into the lane.
      GeometryReader { proxy in
        Path { p in
          let w = proxy.size.width
          let h = proxy.size.height
          p.move(to: CGPoint(x: w * 0.30, y: h))
          p.addLine(to: CGPoint(x: w * 0.48, y: h * 0.55))
          p.move(to: CGPoint(x: w * 0.70, y: h))
          p.addLine(to: CGPoint(x: w * 0.52, y: h * 0.55))
        }
        .stroke(
          LinearGradient(
            colors: [Color(red: 1.0, green: 0.3, blue: 0.85), Color.clear],
            startPoint: .bottom, endPoint: .top
          ),
          lineWidth: 3
        )
        .blur(radius: 1)
      }
      // A few twinkling "stars" doubling as ceiling lights.
      Stars(count: 24).opacity(0.6)
    }
  }
}

// MARK: - Tropical Island

private struct TropicalIslandBG: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.36, green: 0.78, blue: 0.95),
          Color(red: 0.50, green: 0.88, blue: 0.92),
          Color(red: 0.85, green: 0.95, blue: 0.92),
        ],
        startPoint: .top, endPoint: .bottom
      )
      // Sun.
      Circle()
        .fill(Color(red: 1.0, green: 0.95, blue: 0.65))
        .frame(width: 90, height: 90)
        .blur(radius: 6)
        .offset(x: 80, y: -180)
      Circle()
        .fill(Color(red: 1.0, green: 0.98, blue: 0.85))
        .frame(width: 72, height: 72)
        .offset(x: 80, y: -180)
      // Distant island silhouette + ocean band.
      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height
        Path { p in
          p.move(to: CGPoint(x: 0, y: h * 0.62))
          p.addQuadCurve(
            to: CGPoint(x: w * 0.45, y: h * 0.55),
            control: CGPoint(x: w * 0.22, y: h * 0.50)
          )
          p.addQuadCurve(
            to: CGPoint(x: w, y: h * 0.62),
            control: CGPoint(x: w * 0.72, y: h * 0.48)
          )
          p.addLine(to: CGPoint(x: w, y: h * 0.66))
          p.addLine(to: CGPoint(x: 0, y: h * 0.66))
          p.closeSubpath()
        }
        .fill(Color(red: 0.20, green: 0.55, blue: 0.42))
      }
      VStack {
        Spacer()
        LinearGradient(
          colors: [
            Color(red: 0.08, green: 0.50, blue: 0.78),
            Color(red: 0.20, green: 0.65, blue: 0.85),
          ],
          startPoint: .top, endPoint: .bottom
        )
        .frame(height: 100)
        Rectangle()
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.95, green: 0.85, blue: 0.62),
                Color(red: 0.88, green: 0.75, blue: 0.50),
              ],
              startPoint: .top, endPoint: .bottom
            )
          )
          .frame(height: 60)
      }
      // Palm trees in the foreground.
      HStack(alignment: .bottom) {
        PalmTree(
          trunkColor: Color(red: 0.30, green: 0.20, blue: 0.10),
          leafColor: Color(red: 0.10, green: 0.40, blue: 0.20)
        )
        .frame(width: 80, height: 220)
        Spacer()
        PalmTree(
          trunkColor: Color(red: 0.32, green: 0.22, blue: 0.12),
          leafColor: Color(red: 0.12, green: 0.45, blue: 0.22)
        )
        .frame(width: 70, height: 190)
      }
      .padding(.horizontal, 6)
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
  }
}

private struct PalmTree: View {
  let trunkColor: Color
  let leafColor: Color
  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      ZStack(alignment: .bottom) {
        // Curved trunk.
        Path { p in
          p.move(to: CGPoint(x: w * 0.45, y: h))
          p.addQuadCurve(
            to: CGPoint(x: w * 0.55, y: h * 0.20),
            control: CGPoint(x: w * 0.65, y: h * 0.6)
          )
        }
        .stroke(trunkColor, style: StrokeStyle(lineWidth: w * 0.13, lineCap: .round))
        // Frond cluster.
        ForEach(0..<6, id: \.self) { i in
          Capsule()
            .fill(leafColor)
            .frame(width: w * 0.55, height: 7)
            .rotationEffect(.degrees(Double(i) * 30 - 75))
            .offset(x: w * 0.05, y: -h * 0.78)
        }
        // Coconuts cluster.
        Circle()
          .fill(Color(red: 0.30, green: 0.18, blue: 0.08))
          .frame(width: 8, height: 8)
          .offset(x: w * 0.35, y: -h * 0.74)
        Circle()
          .fill(Color(red: 0.25, green: 0.15, blue: 0.06))
          .frame(width: 7, height: 7)
          .offset(x: w * 0.55, y: -h * 0.71)
      }
    }
  }
}

// MARK: - Sunset Strip

private struct SunsetStripBG: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.85, green: 0.18, blue: 0.45),
          Color(red: 1.0, green: 0.50, blue: 0.40),
          Color(red: 1.0, green: 0.70, blue: 0.50),
          Color(red: 0.45, green: 0.10, blue: 0.45),
        ],
        startPoint: .top, endPoint: .bottom
      )
      // Big setting sun with concentric heat halos.
      ZStack {
        Circle()
          .fill(Color(red: 1.0, green: 0.85, blue: 0.40).opacity(0.4))
          .frame(width: 220, height: 220)
          .blur(radius: 25)
        Circle()
          .fill(Color(red: 1.0, green: 0.78, blue: 0.30))
          .frame(width: 130, height: 130)
      }
      .offset(y: -50)
      // Distant mountain silhouette.
      MountainSilhouettes(color: Color(red: 0.30, green: 0.05, blue: 0.30), baseY: 0.62)
      // Two retro horizontal stripes (Miami Vice).
      VStack(spacing: 6) {
        Spacer()
        Rectangle()
          .fill(Color(red: 1.0, green: 0.20, blue: 0.55))
          .frame(height: 1.5)
        Rectangle()
          .fill(Color(red: 0.30, green: 0.85, blue: 1.0))
          .frame(height: 1.5)
          .opacity(0.7)
        Spacer().frame(height: 60)
      }
      // Palm tree silhouettes.
      HStack(alignment: .bottom) {
        PalmTree(trunkColor: .black, leafColor: .black)
          .frame(width: 70, height: 200)
        Spacer()
        PalmTree(trunkColor: .black, leafColor: .black)
          .frame(width: 60, height: 170)
      }
      .padding(.horizontal, 14)
      .frame(maxHeight: .infinity, alignment: .bottom)
    }
  }
}

// MARK: - Desert Dunes

private struct DesertDunesBG: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 1.0, green: 0.72, blue: 0.40),
          Color(red: 1.0, green: 0.85, blue: 0.55),
          Color(red: 0.95, green: 0.78, blue: 0.50),
        ],
        startPoint: .top, endPoint: .bottom
      )
      Circle()
        .fill(Color.white.opacity(0.4))
        .frame(width: 180, height: 180)
        .blur(radius: 30)
        .offset(x: 60, y: -160)
      Circle()
        .fill(Color.white.opacity(0.95))
        .frame(width: 80, height: 80)
        .offset(x: 60, y: -160)
      // Distant pyramids.
      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height
        Path { p in
          p.move(to: CGPoint(x: w * 0.55, y: h * 0.45))
          p.addLine(to: CGPoint(x: w * 0.78, y: h * 0.62))
          p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.62))
          p.closeSubpath()
          p.move(to: CGPoint(x: w * 0.20, y: h * 0.52))
          p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.62))
          p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.62))
          p.closeSubpath()
        }
        .fill(Color(red: 0.78, green: 0.55, blue: 0.30))
      }
      // Dune layers (stacked curves) for foreground depth.
      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height
        ZStack {
          Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.65))
            p.addQuadCurve(
              to: CGPoint(x: w, y: h * 0.65),
              control: CGPoint(x: w * 0.5, y: h * 0.55)
            )
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
          }
          .fill(Color(red: 0.92, green: 0.74, blue: 0.42))
          Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.78))
            p.addQuadCurve(
              to: CGPoint(x: w, y: h * 0.74),
              control: CGPoint(x: w * 0.6, y: h * 0.68)
            )
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
          }
          .fill(Color(red: 0.85, green: 0.65, blue: 0.34))
          Path { p in
            p.move(to: CGPoint(x: 0, y: h * 0.92))
            p.addQuadCurve(
              to: CGPoint(x: w, y: h * 0.88),
              control: CGPoint(x: w * 0.45, y: h * 0.82)
            )
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
          }
          .fill(Color(red: 0.78, green: 0.58, blue: 0.28))
        }
      }
      // A lone cactus.
      Cactus()
        .frame(width: 50, height: 100)
        .padding(.leading, 30)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
  }
}

private struct Cactus: View {
  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      ZStack {
        RoundedRectangle(cornerRadius: w * 0.25)
          .fill(Color(red: 0.18, green: 0.42, blue: 0.22))
          .frame(width: w * 0.35, height: h * 0.8)
          .offset(y: h * 0.1)
        RoundedRectangle(cornerRadius: w * 0.18)
          .fill(Color(red: 0.18, green: 0.42, blue: 0.22))
          .frame(width: w * 0.22, height: h * 0.35)
          .offset(x: -w * 0.28, y: -h * 0.1)
        RoundedRectangle(cornerRadius: w * 0.15)
          .fill(Color(red: 0.18, green: 0.42, blue: 0.22))
          .frame(width: w * 0.5, height: h * 0.12)
          .offset(x: -w * 0.18, y: -h * 0.27)
        RoundedRectangle(cornerRadius: w * 0.18)
          .fill(Color(red: 0.16, green: 0.40, blue: 0.20))
          .frame(width: w * 0.20, height: h * 0.30)
          .offset(x: w * 0.28, y: -h * 0.05)
        RoundedRectangle(cornerRadius: w * 0.15)
          .fill(Color(red: 0.16, green: 0.40, blue: 0.20))
          .frame(width: w * 0.45, height: h * 0.10)
          .offset(x: w * 0.18, y: -h * 0.20)
      }
    }
  }
}

// MARK: - Jungle Temple

private struct JungleTempleBG: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.10, green: 0.32, blue: 0.20),
          Color(red: 0.18, green: 0.42, blue: 0.25),
          Color(red: 0.10, green: 0.30, blue: 0.18),
        ],
        startPoint: .top, endPoint: .bottom
      )
      // Light rays from above.
      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height
        ForEach(0..<3, id: \.self) { i in
          Path { p in
            let baseX = w * (0.25 + 0.25 * CGFloat(i))
            p.move(to: CGPoint(x: baseX - 25, y: 0))
            p.addLine(to: CGPoint(x: baseX + 25, y: 0))
            p.addLine(to: CGPoint(x: baseX + 5, y: h * 0.6))
            p.addLine(to: CGPoint(x: baseX - 5, y: h * 0.6))
            p.closeSubpath()
          }
          .fill(Color.white.opacity(0.08))
          .blur(radius: 6)
        }
      }
      // Stepped pyramid temple silhouette in the mid-distance.
      GeometryReader { proxy in
        let w = proxy.size.width
        let h = proxy.size.height
        let baseY = h * 0.65
        ZStack {
          ForEach(0..<4, id: \.self) { i in
            let tier = CGFloat(4 - i)
            let tierW = w * (0.30 + tier * 0.05)
            let tierH: CGFloat = 24
            let yOffset = baseY - tier * tierH
            Rectangle()
              .fill(Color(red: 0.20, green: 0.30, blue: 0.18))
              .frame(width: tierW, height: tierH)
              .position(x: w / 2, y: yOffset)
          }
          Rectangle()
            .fill(Color.black.opacity(0.7))
            .frame(width: 18, height: 28)
            .position(x: w / 2, y: baseY - 14)
        }
      }
      // Hanging vines from the top.
      GeometryReader { proxy in
        let w = proxy.size.width
        ForEach(0..<5, id: \.self) { i in
          let x = w * (0.05 + 0.22 * CGFloat(i))
          Path { p in
            p.move(to: CGPoint(x: x, y: 0))
            p.addQuadCurve(
              to: CGPoint(x: x + 12, y: 110),
              control: CGPoint(x: x + 22, y: 60)
            )
          }
          .stroke(
            Color(red: 0.05, green: 0.20, blue: 0.10),
            style: StrokeStyle(lineWidth: 2, lineCap: .round))
          Ellipse()
            .fill(Color(red: 0.18, green: 0.45, blue: 0.22))
            .frame(width: 14, height: 6)
            .position(x: x + 14, y: 105)
        }
      }
      // Fern fronds in the foreground.
      HStack(alignment: .bottom) {
        Fern().frame(width: 100, height: 110)
        Spacer()
        Fern().frame(width: 80, height: 90)
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
      .opacity(0.85)
    }
  }
}

private struct Fern: View {
  var body: some View {
    GeometryReader { proxy in
      let w = proxy.size.width
      let h = proxy.size.height
      ZStack(alignment: .bottom) {
        ForEach(0..<5, id: \.self) { i in
          let angle = Double(i) * 22 - 44
          Capsule()
            .fill(Color(red: 0.10, green: 0.32, blue: 0.16))
            .frame(width: 6, height: h)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .offset(x: w / 2 - 3)
        }
      }
    }
  }
}

// MARK: - Dragon Shrine

private struct DragonShrineBG: View {
  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.15, green: 0.02, blue: 0.05),
          Color(red: 0.40, green: 0.05, blue: 0.10),
          Color(red: 0.65, green: 0.12, blue: 0.10),
        ],
        startPoint: .top, endPoint: .bottom
      )
      Stars(count: 30).opacity(0.8)
      Circle()
        .fill(Color(red: 1.0, green: 0.55, blue: 0.30).opacity(0.35))
        .frame(width: 160, height: 160)
        .blur(radius: 16)
        .offset(x: -70, y: -180)
      Circle()
        .fill(Color(red: 1.0, green: 0.78, blue: 0.50))
        .frame(width: 90, height: 90)
        .offset(x: -70, y: -180)
      MountainSilhouettes(color: Color(red: 0.10, green: 0.02, blue: 0.04), baseY: 0.55)
      // Pagoda silhouette.
      VStack(spacing: -2) {
        ForEach(0..<4, id: \.self) { i in
          let width = 80 + CGFloat(i) * 30
          ZStack {
            Rectangle().fill(Color.black).frame(width: width - 20, height: 28)
            Path { p in
              p.move(to: CGPoint(x: 0, y: 10))
              p.addQuadCurve(
                to: CGPoint(x: width, y: 10),
                control: CGPoint(x: width / 2, y: -4))
              p.addLine(to: CGPoint(x: width - 12, y: 14))
              p.addLine(to: CGPoint(x: 12, y: 14))
              p.closeSubpath()
            }
            .fill(Color.black)
            .frame(width: width, height: 14)
            .offset(y: -14)
          }
        }
      }
      .frame(maxHeight: .infinity, alignment: .bottom)
      .padding(.bottom, 30)
      // Floating paper lanterns.
      ForEach(0..<3, id: \.self) { i in
        Circle()
          .fill(Color(red: 1.0, green: 0.45, blue: 0.20))
          .frame(width: 14, height: 18)
          .blur(radius: 1)
          .offset(
            x: CGFloat([-90, 80, 30][i]),
            y: CGFloat([-30, -90, -150][i])
          )
      }
    }
  }
}
