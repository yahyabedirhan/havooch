# Maintainer feedback, 7 and 8 October 2026

The maintainer's own words from the grilling and prototype session that followed `Mate: Make opening a video and connecting any agent simple for new users` (#76). Dictation slips are fixed ("Havuç", "Habuch", "Haiku" are Havooch; "Py" is Pi); the wording is otherwise kept. The itemized decisions are in [2026-10-08-decisions.md](2026-10-08-decisions.md). The motivation part of the session is also kept in the maintainer's notes as HUMA-1, "Brainstorm: human-agent interaction, Havooch and Havooch Studio".

## Opening a video and connecting an agent

> Yes I want one command to open a video: the CLI command, which can be used by both agents and also humans on the CLI. When this command is used I want the Havooch window to be focused so that the user can immediately see it. I don't want it to be opened somewhere in the background.

> So harnesses, the first tier, are: Claude Code Desktop, Claude Code CLI, Codex Desktop, Codex CLI, Cursor Desktop, Cursor CLI, Pi, OpenCode. I want to check all of these harnesses with a live QA.

> Currently the issue is that when I open the Havooch app, it shows me that there is no live connection with an agent but it doesn't guide me on how I can make that connection. Also what are the skills and what are the other tools I maybe need to set up to make that connection possible? For example in the Shipyard project, we have a settings menu where we click and select whether the Shipyard CLI and the Shipyard skills are working fine. I think we need something similar here in Havooch as well. Not necessarily a setup connection but just, for example, giving a prompt to the user that they can paste into their harness conversation so it will trigger the conversation on the agent side. For this to work a skill and a CLI need to be installed on the user's machine so that agents can understand how they can interact with Havooch.

> There are two ways to initiate this connection: 1. They can start by manually opening the Havooch app, selecting a video by themselves, and then seeing that there is no agent session connected. They can walk through the application and set up the connection. 2. They can start by telling their agents directly, for example in Claude Desktop or Claude Code Desktop, to open this video with Havooch. The session in the current harness sets up all the listening and all the communication so that users don't need to do anything else. This will be the simplest flow possible.

> Yes, this should be promoted to the users because without the skill it is hard for agents to understand how to use Havooch, because this is a new app. It can be started by "No session available" in the bottom-right area of the application. Or there might be a new settings button on the top-right header that helps users to reach the configuration and the setup details.

## Why Havooch exists

> I want to be able to communicate with my agents, to enhance human-agent communication. I want my own agents to help me with this review lifecycle. I don't want to lose my existing agents and I don't want to use some kind of third-party agent that talks to my agent.

> What I want to make is to make it too obvious, too easy to connect. They don't have to do anything. They just click start listening and done: their existing agents already start listening.

## The player and versions

> Let's say users just open a video and they ask questions about the video. No more versions are needed. But at the time where the user wants to change the video based on the feedback, I think there should be a project created automatically, or through a CLI command that agents can run. The project should be a container. Do not enforce where the videos live. A config file like the config.toml we have in Swift Lab or Shipyard defines the name of the project and the versions and where the versions live in the file system with the full path. That will be a nice balance between opening the initial video as fast as possible and, as the user iterates on it, containing it in a project so that further videos can be linked together. By automatically I don't mean Havooch as an application; the agent that uses Havooch already has the skill and the CLI, so agents should do that on behalf of the user.

> Projects can live in a single config.toml file. Look at how Shipyard and Swift Lab work.

> Path and label are needed in the config. We can move settings to the file too, but not all the theme variables; the theme stays a separate file that holds the colour variables and config.toml decides which theme to use. One video can be in two projects. Havooch doesn't care about it. The agents manage the state on behalf of users and they can fix those errors. Havooch doesn't enforce it. The threads will be attached to the project so that while working on multiple versions the threads aren't deleted when we move on to the next version.

> App state is not a part of this config.toml. Threads are tagged as version one, then version two. I'm not currently certain about what the user experience will be. Don't enforce rules here. Just keep the thread open. I should be able to use the old threads as well as new threads. The system doesn't close them automatically. If we already have a thread on a video, creating the project from that video moves those threads into the project. If I open the same video through Havooch, I see that video through a project automatically. Once a video is contained by a project, its threads move to the project. If another project has the video, it starts from fresh.

> If a video is in two projects and Havooch opens it with the CLI, it should open from the most recent, and there should be an explicit parameter to open it with another project. Anchor by path; never hide or drop a thread because of a change.

## Prototype feedback: project versions

> For the project thread list I think the version tree looks really good. What happens when there are 50 versions? I really care about seeing the last n versions really quickly and being able to reach the previous versions, hidden behind a dropdown or something.

> For the version switcher I like version 1 the most. It gives quick access to the last couple of versions. Make the comparison flow clearer: open a popover when you click the comparison button. I see two windows as a small representation of the comparison window. I click on the left and pick version 1, I click on the right and pick version 3. That comparison control should be a separate component.

> For the project thread list V5 looks really good. The version switcher V5 looks really good. For the compare control I liked side by side, flip and slider; these are really powerful features that I definitely want to include. I also like the switch button that switches left and right.

> Compare control V4 works pretty well. This affects not only the compare control itself but also how versions are compared in the actual video player. I am okay with the scope. I don't like the stacked-layers icon; don't use it anywhere in the application at any point.

## Agent onboarding decisions

> One listener per project; that has an impact on the listening system and the window system. To work on different projects in parallel, we should allow opening multiple windows. Think of it like VS Code windows: I can open a new window, which is empty at first, and open a video or a project in it. One listener per window; each window holds a project with versions of a video, or a single video without a project.

> If the skill is not installed we should let users install it through the application so that they know it exists. A user who just downloaded the application doesn't know how to use it, so we should give them a dedicated onboarding flow when they first open the app, to set up the necessary tools and walk them through their first session by typing a prompt in their agent. If users skip everything and send messages without a listener, there should be a way of telling them, when they send and when they click "No listener".

> You don't need to worry about how to run each harness. For any harness, users should be able to talk to their agents once they install the Havooch skill, and their agents should understand how to use it.

> We shouldn't be aggressive about being the default video player, but we should let users open a video quickly with Havooch. A Raycast extension could be a separate new feature.

> A demo agent can be part of the Havooch skill: a reference document in the skill used only for the demo, with details useful for beginners. After they learn, in the regular flow, the demo reference isn't used again.

> Some users install skills globally and some per project. By default install globally in one click. For a repository, show the command to copy and paste.

> I don't want one release per effort any more. Define efforts by meaning and release after they're done, not necessarily one release per effort.

> Users of Havooch know about skills. It is the user's responsibility to install the skill. It is our responsibility to show users when the skill is not installed.

## Prototype feedback: onboarding

> First-run V1 (Welcome, Tools, Connect, Try it) looks good. The demo prompt should be like "Use Havooch to open the demo video and listen for my feedback". I like V3's in-app guidance as an optional tour, for users who opened and closed the app without finishing setup. Its entry point can be in the top-right header, shown while steps are incomplete.

> Copying the prompt is not an app state. We shouldn't show "you pasted the prompt and we wait". Waiting for a connection can be a state.

> The pill flow (No agent, set up an agent step by step) is the experience I was trying to get. The first-run onboarding focuses on new users and the listener area on day-to-day users. A popover looks more native than the expanding footer. A standalone "Connect an agent" view is best for flexibility, but V3's separate cards looked non-native; don't overuse cards.

> There should be a single view that guides users to setup. The No agent button, the Send button with no listener, and the top-right menu all open the same "Connect an agent" view on the right sidebar. Command line and skill shouldn't be separate menu items; they are part of that view.

> Keep "Finish setup" as a separate button; it disappears once setup is finished. Give the tour ring padding so it doesn't touch the content. Command line and skill sections expand and collapse; when linked, show "Linked", not "On PATH". I like the experience but not the appearance; keep the experience and prototype the look. Keep the "3 messages wait for an agent" box.

> We can 100% deterministically know that the skill isn't installed globally, but if it's inside the user's repository we can't. Be careful about this deterministic requirement throughout onboarding and listening.

> I like V4 (step timeline). Titles: "`havooch` command line" and "`/havooch-mate` skill". Put the prompt text on top and the copy button in a footer. Show what the connected state looks like.

> White text on that colour doesn't have enough contrast. Use another colour, maybe in other parts of the app as well.

> Don't use em dashes anywhere, and not a spaced dash either. Say "to listen again later", not "tomorrow". Never use one-sided borders on cards: not left, not right, top or bottom. For things we cannot detect, don't assume they're missing; say we couldn't detect it, and if they think it's installed, paste the prompt and it'll continue from there. The prompt uses the skill invocation: `/havooch-mate listen for my feedback on <video>` for Claude Code, `$havooch-mate …` for Codex, and whatever Cursor, Pi and OpenCode use.

## Splitting the work

> Making five different efforts makes this a very long period of implementation. Everything is working in harmony and cohesion. Make one big effort, defined by its final state in the spec, broken into tickets in a topological order that maximises parallel work, so the orchestrator can delegate to sub-agents.

> Without any exceptions I want everything written somewhere, in the specs, the docs or a decision format, where all agents can read it. The final state works: the multi-window, multi-agent parallel project structure, and every detail of onboarding, with the easy path to connect an existing agent from an existing harness.
