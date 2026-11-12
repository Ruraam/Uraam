> **Archived reference — not current operational guidance.** This file belongs to an earlier device-specific Ruvomain Protocol workflow. URAAM's current implementation and safety behavior may differ. Do not apply package lists, tiers, tuning targets or replacement instructions from this page without independently validating them for your exact device and firmware. Start with the [current documentation index](README.md), [Quick Start](Quick-Start-Guide.md) and [Safety and Recovery](Safety-and-Recovery.md).

---

**You can import your personal JSON list file or your Canta/UAF JSON list in ./Configs/debloat. [instructions](Configs/debloat/README.md).**

---
**This list below is optimized for S24+ (Exynos)**

`⚠️ Use Tier 3 with caution if you rely on Knox/Samsung Pay or core system integrity features.**`

### 🟢 TIER 1: Redundancy & Telemetry (Safe)
Useless software layers or redundant telemetry services. No impact on core One UI functionality.
 
**• Bixby & Assistants:**

`com.samsung.android.bixby.agent`:
Bixby voice assistant

`com.samsung.android.bixbyvision.framework`:
Bixby image recognition engine.

`com.samsung.android.visionintelligence`:
Dedicated vision AI
 
**• Personalization & UI Services:**

`com.samsung.android.app.taskedge`:
Edge panel functionality

`com.samsung.android.aircommandmanager`:
S-Pen feature management

`com.samsung.android.bluelightfilter`:
Native blue light filter

`com.sec.android.easyonehand`:
One-handedoperation mode

`com.samsung.android.app.earphonetypec`:
USB-C audio accessorymanagement

`com.samsung.android.inputshare`:
Multi-device keyboard/mouse sharing
 
**• Telemetry & Diagnostics:**

`com.samsung.android.dqagent`:
Samsung Quality Agent

`com.android.devicediagnostics`:
Google hardware diagnostics tool

`com.samsung.android.rampart`:
Security/system telemetry service

`com.samsung.android.bbc.bbcagent`:
Samsung "Big Data" collection service.

`com.samsung.android.dsms`:
System log reporting service

`com.sec.android.app.factorykeystring`:
Factory test keys/logs
 
**• Device Services:**

`com.samsung.android.beaconmanager`:
Proximity beacon manager

`mcom.samsung.android.mcfds`:
Multi-device connectivity framework.

`com.samsung.android.mdx.kit`:
Multi-device development kit

`com.samsung.cmh`:
Samsung Connection Manager

`com.samsung.android.mcf.autohotspot`:
Auto-hotspot functionality
 
**• Multimedia & AR:**

`com.sec.android.mimage.avatarstickers/aremojieditor`:
AR Emojicreation and management.

`com.android.avatarpicker`:
System avatar selector.

`com.samsung.android.app.camera.sticker.facearavatar.preload`:
Camera AR stickers.

`com.samsung.android.faceservice`:
Facial recognition service.

`com.sec.android.mimage.photoretouching`:
Native photo retouching tool.

`com.samsung.app.newtrim`:
Video trimming editor.

`com.samsung.android.vtcamerasettings`:
Advanced video camera settings.

`com.android.dreams.basic/phototable`:
Interactive screensavers.
 
**• Miscellaneous:**

`com.android.egg`:
Android Easter egg.

`com.samsung.android.brightnessbackupservice`:
Auto-brightness preference backup.

`com.samsung.safetyinformation`:
Legal safety manual.

`com.sec.android.provider.badge`:
Notification badgecounts.

`com.samsung.android.forest`:
Samsung Digital Wellbeing.

`com.sec.android.app.parser`:
System configuration parser.

`com.samsung.android.aware.service`:
Presence and context sensors.
 
---
### 🟡 TIER 2: Optional Features (Moderate)
Ecosystem-related services. Disable only if you do not use these features.

**Include tier 1 and:**
 
**• Samsung Ecosystem:**

`com.samsung.android.mydevice`:
"My Device" / support app.

`com.samsung.android.mdecservice`:
Calls/SMS on other Samsung devices.

`com.sec.android.easyMover.Agent/smartswitchassistant`:
Smart Switch data transfer.

`com.samsung.android.callbgprovider`:
Personalized call backgrounds.
 
**• Google/Cloud Services:**

`com.google.ar.core`:
Augmented Reality service.

`com.google.android.aicore/aicore.services`:
Local Google AI engine.

`com.google.android.federatedcompute`:
Distributed computing (AI telemetry).

`com.google.android.apps.restore`:
Google backup restoration.

`com.google.android.as`:
Android System Intelligence.

`com.google.android.ondevicepersonalization.services`:
On-device AI personalization.

`com.google.android.appsearch.apk`:
Google search engine.

`com.google.android.health.connect.backuprestore`:
Connected health data.

`com.google.android.adservices.api`:
Google advertising services.
 
**• Connectivity:**

`com.samsung.android.net.wifi.wifiguider`:
Samsung Wi-Fi guide.

`com.samsung.android.audiomirroring`:
Audio mirroringto other screens.

`com.sec.android.app.bluetoothagent`:
Bluetooth management agent.

`com.android.bluetoothmidiservice`:
Bluetooth MIDI support.

`com.android.ons`:
OpportunisticNetworkService (network switching).
 
**• Security/Knox:**

`com.samsung.android.knox.attestation`
`com.samsung.android.knox.er`
`com.samsung.android.knox.mpos`:
Knox services (Enterprise/Payment).

`com.samsung.android.authfw`:
Samsung authentication framework.
 
**• System & Miscellaneous:**

`com.sec.hearingadjust`:
Sound adaptation (Adapt Sound)

`com.samsung.android.app.omcagent`:
Carrier-specific configurations.

`com.android.bookmarkprovider`:
Browser bookmark manager.

`com.android.calllogbackup`:
Call history backup.

`com.sec.android.CcInfo`:
Closed Caption information.

`com.sec.android.app.chromecustomizations`:
Chrome customizations.

`com.android.providers.partnerbookmarks`:
Pre-installed partnerbookmarks.

`com.android.wallpaperbackup`:
Wallpaper backup.

`com.samsung.slsi.telephony.silentlogging`:
Telephony Silent logging

`com.sec.android.app.qsfastpairoverlay`:
Fast Pair connection overlay.

`com.sec.bcservice`:
Network Broadcast service.
 
---
### 🔴⚠️ TIER 3: Replacement Required (Advanced) Fundamental packages.
Disable only after installing a viable alternative.

**Include tier 1 + tier 2 and:**
 
**• Keyboard:**
`com.touchtype.swiftkey`:
Default keyboards
 
**• Interface/Setup:**

`com.sec.android.app.SecSetupWizard`:
Post-reset Samsung setup wizard

`com.google.android.setupwizard`:
Post-reset Google setup wizard

`android.autoinstalls.config.samsung`:
Automatic app installation on first boot.
 
**• Communication:**
`com.samsung.android.app.contacts`,
`com.sec.android.widgetapp.easymodecontactswidget`:
Contact management
 
**• Camera Core:**

`com.sec.android.app.camera`:
Native camera interface
 
**• System Security:**

`com.google.android.verifier`,
`com.google.android.verifier.overlay`:
(Play Protect security verification).
 
Technical note: This list is a working base. As always, system integrity dependson the balance between removing telemetry and maintaining crucial system services.
