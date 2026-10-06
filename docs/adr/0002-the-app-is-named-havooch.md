# The app is named Havooch

The app was built as Video Review, a name that describes it and that no one can own or find. Before its first public release it is named **Havooch**, after the maintainer's orange and white cat, Havuç (#51). "Havuç" is Turkish for "carrot". "Havooch" spells how it sounds, hah-VOOCH, so everyone types and says it the same way: the display name never uses the letter ç. Its logo is the cat's head (logo v2 "Havuç", `assets/images/logo/v2-havuc/`), and the app icon is that head on a white tile, to sit beside Shipyard's in the Dock.

Earlier candidates were rejected because other products already use them: Frameback, Retake, Replai, Recue, Framenote and Selu.

## What changed, and what kept its name

- The app is `Havooch.app`, bundle id `com.yahyabedirhan.havooch`, and its command is `havooch`. The app's executable is `HavoochApp`, not `Havooch`: on a case-insensitive disk `Havooch` and `havooch` would be one file in `.build`.
- The environment variables are `HAVOOCH_*`. Each one's earlier name, `VIDEO_REVIEW_*`, is read when the new one isn't set, so agents' setups and scripts keep working (`AppVariable`). The app and the command only ever write the new names.
- The listener skill is `havooch-mate`, and a commit it makes for a message ends `Havooch-Message: <message-id>`.
- The support folder is `~/Library/Application Support/Havooch/`. A launch on the person's own data moves every item of `~/Library/Application Support/Video Review/` into it (`EarlierSupportFolder`), so an update keeps every review, theme and setting. It never runs when `HAVOOCH_SUPPORT_DIR` moves the support folder (every demo run and test), never while the earlier app (`com.yahyabedirhan.video-review`) runs, and never overwrites an item the new folder has; the earlier app's socket and demo pointer stay behind. Moving at launch, not leaving a link or reading both folders, keeps one place for the data.
- The Swift modules keep their names (`ReviewCore`, `ReviewApp`, `ReviewWire` and the rest), and so does the domain type `VideoReview`, the review of one video: they name what the code does, not the product, and renaming them would churn every file for nothing a person sees.
- `~/Library/Caches/video-review/` keeps its name: the module cache and the agents' install lock are shared by checkouts of both names.
- The GitHub repository is renamed `yahyabedirhan/havooch` by the maintainer, as an outward step of its own; GitHub redirects the old URL. The maintainer renamed it on 2026-10-06, and the agents' docs name `yahyabedirhan/havooch` since.
- The sample video says "This is Video Review": its narration and its transcripts stay as recorded.
