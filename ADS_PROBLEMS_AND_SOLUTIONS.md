# MrPlay — Ads: problems and solutions

## Rule
Never disable, geo-block, or skip ad requests for any country (Tunisia, Algeria, etc.). Grow fill by adding demand, not by cutting traffic.

Only simple, non-intrusive ads (banner / native). No rewarded ads, no app-open ads, no interstitials — nothing that bothers users.

## Problems

1. **Very low eCPM (~$0.06–0.07 blended).**
   - Banner on the hub page earned almost nothing.
2. **Low match rate in Tunisia.**
   - ~82,739 requests, 10.41% match rate, $0.04 eCPM.
   - This drags the blended eCPM down.
3. **High-paying countries get very few requests.**
   - USA $1.33 (only 41 requests), Germany $0.46, France $0.27.
   - Audience is mostly in low-demand markets.
4. **Low-impact formats.** Standard banners are easy to ignore.
5. **Native ad did not show (fixed).**
   - Old unit `…/9057816022` was created with the wrong setup and returned `Request Error: No ad to show` (iOS code 1, no fill).
   - New native unit `…/6399771207` works: test ads now appear on the registered test device.

## Done

- Replaced the hub banner with a Native Advanced ad (`lib/widgets/native_ad_slot.dart`).
- Swapped to the new native ad unit ID in `lib/ad_config.dart`.
- Moved the native ad below the platforms grid in `lib/presentation/pages/hub_page.dart`.
- Removed the temporary on-screen error text.
- Build is `1.0.2+4`, built by `.github/workflows/ios-testflight.yml` on push to `master` / `v2-tabs`.

## Solutions (planned)

1. **Mediation / Open Bidding** to raise fill and eCPM.
   - In AdMob: create a mediation group, enable AdMob Network bidding, add partners.
   - Candidate networks: AppLovin, Meta Audience Network, Unity Ads (optionally Pangle, Mintegral). These often have more MENA demand than Google alone.
   - In the app: add adapters to `pubspec.yaml` (e.g. `gma_mediation_applovin`, `gma_mediation_meta`), run `pod install` in CI, add each partner's `SKAdNetwork` IDs to `ios/Runner/Info.plist`, keep the UMP consent flow.
   - Needs partner accounts and `app-ads.txt` entries.
2. **Waterfall fallback.** Add a low-floor network instance as a last resort for requests that still don't fill.
3. **More simple placements** (banner / native only) in non-intrusive spots, each with mediation, to give more fill chances without bothering users.
4. **Smarter retries, not fewer requests.** Keep requests for every country, keep exponential backoff on failures.
5. **Tier-1 user acquisition** (outside the code): ASO in English, marketing to USA / UK / Canada / Germany / France. This is the biggest income lever.

## Notes

- eCPM is earnings per 1,000 impressions, not per request. A low match rate hurts fill, not eCPM directly.
- Mediation typically adds ~10–50%. It will not fix a low-paying audience mix on its own.
- Interstitial and rewarded ads pay more, but we deliberately do not use them (they bother users).

## Next steps

- [ ] Choose first networks (suggested: AppLovin + Meta + Unity) and create accounts / units.
- [ ] Add mediation adapters, pods and `SKAdNetwork` IDs.
- [ ] Decide extra banner / native placements (non-intrusive only).
- [ ] Review AdMob Reports by country after a few days.
