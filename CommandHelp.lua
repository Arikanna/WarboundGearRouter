-- One public command list for both /wbgr help and About > Useful Commands.
-- Advanced diagnostics and deprecated aliases are deliberately not advertised.
-- Keep descriptions concise for the in-game two-column layout.
WGRPublicCommandHelp = {
    {"/wbgr", "Open Warbound Gear Router."},
    {"/wbgr help", "Show this command list."},
    {"/wbgr mailrouter", "Open Mail Router at a mailbox."},
    {"/wbgr ignore", "Ignore the hovered item type."},
    {"/wbgr unignore", "Stop ignoring the hovered item type."},
    {"/wbgr keep", "Mark the hovered physical copy KEEP; override AUTO routing."},
    {"/wbgr unkeep", "Clear its KEEP mark; return the copy to AUTO routing."},
    {"/wbgr dispose", "Mark the hovered physical copy DISPOSE; override AUTO routing."},
    {"/wbgr undispose", "Clear its DISPOSE mark; return the copy to AUTO routing."},
    {"/wbgr pause", "Pause live routing and gear overlays."},
    {"/wbgr resume", "Resume live routing and gear overlays."},
}
