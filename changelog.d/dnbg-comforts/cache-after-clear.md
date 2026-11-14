Fixed the usage band losing track of things after a `/clear`. Its prompt-cache
estimate stuck at `cache none`, and now counts down again from the first turn
after the clear. A cache lifetime reported by a model switch, the pending-update
hint and the compaction point now carry through a `/clear`, and switching model
after a `/clear` no longer announces a long-saved model as newly saved for all
future sessions.
