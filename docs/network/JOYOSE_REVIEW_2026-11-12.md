# Joyose review — 2026-11-12

Package: `com.xiaomi.joyose`. This is distinct from the Xiaomi Games storefront
(`com.xiaomi.glgm`), Mi Picks/GetApps (`com.xiaomi.mipicks`), and Community
(`com.mi.global.bbs`).

## Evidence from the connected eos

The package-manager dump identifies version `2.2.75`, installed under
`/system/app/Joyose`, with the `SYSTEM` flag and shared system UID 1000. Its
registered components include `smartop.gamebooster.receiver.BoostRequestReceiver`
and `smartop.provider.GameInfoProvider`; it also has Game Booster/Game Turbo
permissions. This supports a role in Xiaomi's game/performance services. It does
not establish every feature or dependency of the package.

The separate endpoint audit attributed eight failed configuration requests to
`mcc.intl.inf.miui.com/cloud/app/getData` to the Joyose process. Those records do
not establish successful data transfer, advertising content, or malware.

## Reference evidence

The [UAD-NG package list](https://github.com/Universal-Debloater-Alliance/universal-android-debloater-next-generation/blob/main/resources/assets/uad_lists.json)
describes Joyose as a GPU tuner/game optimizer and classifies removal as
`Expert`. This is a community project's classification, not a Xiaomi guarantee
about this specific firmware.

The original [Joyose breakage report and discussion](https://github.com/0x192/universal-android-debloater/issues/207)
contains firsthand reports of lost Game Turbo functionality after removal or
disablement, as well as conflicting reports about other effects. It does not
establish that every model or firmware behaves alike.

## Practical conclusion

ADB offers user-0 uninstall and disable operations for a named package, but this
review has not tested whether MIUI permits either on Joyose. Temporary disablement
would be the first reversible experiment, followed by checking the owner's games
and performance features. Removing it by default is not supported by the evidence.

Joyose remains installed and enabled after this read-only review. No removal,
disablement, root, or firmware modification was attempted. The now-general
`--remove-app` option can select it explicitly, but it is not in the default
cleanup profile. Package removal through that option still depends on the
device's response and the normal plan/confirmation workflow.

Local evidence: `results/joyose_review_20261112/package_details.txt` (ignored by
version control). The system-UID permission section can contain entries shared
with other system packages; it should not be treated as evidence that Joyose
exercises every listed permission.
