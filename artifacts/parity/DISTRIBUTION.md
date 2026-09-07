# Distribution check

The addon copied into a project that has nothing else in it, and run four
ways. Written by `tooling/distribution_check.py`.

| what was tried | verdict | detail |
|---|---|---|
| cold import, no cache | PASS | the addon parses with nothing cached |
| editor opens and closes | PASS | the plugin loads in an editor session |
| headless, used for real | PASS | an effect applied and read back |
| 2D targeting | PASS | reachable from a project that has only the addon |
| 3D targeting | PASS | reachable from a project that has only the addon |
| bridges absent | PASS | the addon runs with no Dialogic and no quest system present |
| export, all resources | PASS | the addon exports whole |
| export, selected scenes | PASS | the addon exports whole |

