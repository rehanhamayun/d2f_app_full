# Home and route-planner refinement

The splash headline is “USA & Europe. / West Africa. / Both ways.” Text and actions remain outside the PageView. Touch, mouse and trackpad dragging are enabled; both swipe directions are covered by tests.

The sign-in map is the exact artwork extracted from `design/ChatGPT Image Oct 21, 2026, 03_27_18 AM.png`: x=539, y=216, width=460, height=184. It is bundled as `assets/images/auth_reference_map.png` without regenerating the reference.

The FROM/TO card opens a sliding route-planner sheet. Staff can type a city/country, use suggestions, swap the endpoints and choose Air/Sea/Road. Confirmation updates the card and opens the Ship tab with those values. Both parcel dropdowns support the existing locations in either direction, plus a custom city supplied through the planner. No rate or delivery estimate is invented.

The navigation dock keeps all four tab labels visible, uses an animated gold active indicator, and is centered on wide Chrome windows. Existing tab state is retained.

## Generated home artwork

Generated with the built-in image_gen tool, saved as quality-90 JPEGs, and bundled locally. Existing SVG source assets are retained.

### assets/images/home_register_hero.jpg

Use case: product-mockup. Asset type: full-bleed portrait background artwork for Register Parcel action card in a premium international shipping mobile app. Refined photorealistic 3D product render of a beautifully detailed kraft cardboard shipping parcel, folded corrugated edges, golden yellow packing tape, white shipping label with a small simple abstract barcode but no writing, a slim navy handheld barcode scanner beside it and a small elegant white cargo jet flying behind at the upper right. Main parcel occupies the upper two thirds and right side of frame, oversized and tangible, balanced rich premium composition. Deep midnight navy to muted indigo studio backdrop. Realistic tactile materials, sophisticated soft studio lighting and edge highlights, clean professional logistics advertising aesthetic, not cartoon or clay toy. Bottom quarter and lower left clean very dark navy negative space for title added separately in Flutter. Tall portrait 3:4 composition, objects fully in frame. No letters, words, logos, watermark, interface, arrows, button or outer frame.

### assets/images/home_track_hero.jpg

Use case: product-mockup. Asset type: full-bleed landscape background artwork for Track Parcel action card in premium shipping mobile app. Sophisticated photorealistic 3D product render of a slender midnight navy smartphone with a blue map on its glass screen, a bright golden physical location pin emerging above the screen, elegant curved gold route line, a tiny realistic white delivery truck beside it. Main composition is on the RIGHT half and upper part, left and lower-left is clean deep navy-blue negative space for code-added readable card title. Rich cobalt blue to midnight navy seamless studio backdrop, realistic metal, glass, tactile model surfaces, crisp refined lighting, premium editorial product photography feel. Landscape 3:2 aspect ratio. No text, numbers, letters, brand logos, UI buttons, watermark, frame. Not a cartoon, no human, no confetti, no gratuitous blobs.

### assets/images/home_parcels_hero.jpg

Use case: product-mockup. Asset type: full-bleed landscape background artwork for All Parcels action card in premium shipping mobile app. A refined photorealistic 3D product render of a beautifully arranged three-piece stack of kraft shipping cartons with golden yellow tape and small blank white shipping labels on a low navy pallet, one golden parcel slightly in front, a slim upright navy clipboard with three subtle abstract white lines behind them. Composition compact on RIGHT half and upper part. LEFT and lower-left is clean dark teal negative space for code-added readable card title. Deep teal to midnight navy seamless studio backdrop, tactile corrugated cardboard, physically accurate realistic materials, premium soft studio lighting and clear silhouette, sophisticated professional shipping product photography aesthetic, not cartoon or toy. Landscape 3:2 aspect ratio. No text, letters, numbers, brand logos, UI, arrows, button, frame or watermark.

## Verification

`test/home_experience_test.dart` covers mouse/touch swipes from the splash text, fixed foreground bounds, route validation and swapping, typed cities, real parcel-form prefill after repeated selections, and navigation on phone/desktop sizes. Visual captures are in `design/verification-home-refresh/`; refreshed auth captures are in `design/verification-auth/`.
