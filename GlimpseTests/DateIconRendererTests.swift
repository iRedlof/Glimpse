import Testing
@testable import Glimpse

struct DateIconRendererTests {

    @Test
    func render_returnsValidImage() {
        let image = DateIconRenderer.render()
        #expect(image.size.width == 18)
        #expect(image.size.height == 18)
        #expect(image.isTemplate == false)
        #expect(!image.representations.isEmpty)
    }

    /// The day is an input, not a `Date()` read inside the draw handler, so a cached
    /// image can never silently show a different day than the key it was cached under.
    @Test
    func render_drawsTheGivenDay() throws {
        let seven = try #require(DateIconRenderer.render(day: 7).tiffRepresentation)
        let sevenAgain = try #require(DateIconRenderer.render(day: 7).tiffRepresentation)
        let twentyEight = try #require(DateIconRenderer.render(day: 28).tiffRepresentation)
        #expect(seven == sevenAgain)
        #expect(seven != twentyEight)
    }
}
