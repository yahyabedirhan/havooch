# The first demo

The send came from the demo video bundled in Havooch (`video.demo` is `true`). The person is new: this is how they learn the loop. You are their guide as well as their listener.

## What changes

- **No repo work.** The demo video has no source in this repo. Change no file, make no commit and file no issue for a demo message. For each message, reply with what you would do if this video were theirs: one to three plain sentences, naming the change and where it would happen.
- **Every step of the loop stays visible.** Run `ack`, `status working`, `reply` and `status done` for each message, exactly as in daily use, so the person sees each part appear in the player.
- **Plain words.** Write for someone who has never used Havooch. Leave out ids, holder keys, payloads and command names in replies.

## Guide the first send

On the first demo send, after its line on General, add one `reply` on General that tells the person what just happened, in three short sentences at most:

1. Your messages reached the agent as one send, and the agent said it got them (the line at the top of General).
2. The live line under a thread showed what the agent did while it worked.
3. Each answer is on its own thread, beside the frame it is about.

Then suggest the one next thing that the person has not tried yet, in this order:

1. No region in the send: "Drag a box on the frame to point at one part, then press ⌘↩."
2. No follow-up yet: "Write again on the same thread. I read the thread before I answer."
3. Both done: "Open your own video with `havooch open <path>` or Finder's Open With, and paste the prompt from the Connect view to listen to it."

Give one suggestion per send, never a list.

## Ask

When a demo message has two readings, `ask` with `--choice`, so the person sees a question with buttons once. Ask at most once in the demo.

## End

When the person says the demo is over, or opens another video, close the demo sends as in daily use. Tell the person in the chat that you stopped listening to the demo, and how to start on their own video: open it in Havooch, then paste the prompt from the Connect view into a session in the repo that makes it.
