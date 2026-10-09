MAX TOOLS  v3.8
Fast modeling, UV and game-ready tools for Autodesk 3ds Max 2024+
===================================================================

INSTALLATION
------------
1. Put this "Max Tools" folder somewhere permanent (for example D:\Tools\Max Tools).
   The installer links 3ds Max to THIS folder, so do not move or delete it afterwards.
2. Start 3ds Max.
3. Drag "MaxTools_Install.ms" into a viewport (or Scripting > Run Script...).
4. Done. You will get:
   - a "MaxTools" menu in the main menu bar,
   - a MaxTools side bar docked to the left of the viewport,
   - a "MaxTools" action (category "MaxTools") you can put on any toolbar or hotkey.

Add the icon to a toolbar:
   Customize > Customize User Interface > Toolbars > Category: MaxTools
   Drag "MaxTools" onto any toolbar.

Hotkey:
   Customize > Hotkey Editor > search "MaxTools".

UPDATING
--------
Replace the files in this folder with the new versions. No reinstall is needed:
   - MaxTools.ms           -> picked up the next time the panel is opened
   - MaxToolsUI.cs         -> recompiled automatically the next time the panel is opened
   - MaxToolsPacker.cs     -> recompiled automatically on the next Pack
   - MaxTools_SideBar.ms   -> picked up the next time 3ds Max starts

UNINSTALL
---------
Delete this file and restart 3ds Max:
   <3ds Max user scripts>\Startup\MaxTools_Startup.ms
(The exact path is shown at the end of the installation.)

FILES
-----
MaxTools.ms            Main tool (tools + MAXScript bridge)
MaxToolsUI.cs          The panel interface (compiled inside 3ds Max)
MaxToolsPacker.cs      Shape-based UV packer core (compiled inside 3ds Max)
MaxTools_SideBar.ms    Left side bar with the MaxTools button
MaxTools_Install.ms    Installer (run once)
icons\                 Toolbar and side bar icons

FEATURES
--------
Modeling
   Element Detacher       Splits each element into its own object, centers pivots
   Cross-Scene Copy/Paste Move objects between 3ds Max sessions
   UV Shifter             Randomly offsets UVs per element to break texture tiling
   Quick Merge            Auto group, or attach everything into one object
   Reference Image        Textured plane with the image's aspect ratio
   Drop to Ground         Puts objects or whole groups on Z=0 or on the surface below

UV  (works on an Unwrap UVW modifier)
   Seams                  Mark / remove / clear seams, unwrap from seams
   Hard Edge              Select hard edges (from smoothing groups or by angle),
                          or auto-unwrap from them
   Pack                   Shape-based packer: islands fill gaps, fixed pixel padding,
                          rotation None / 90 / Free, optional texel density equalizing
   Straighten             Align shells, rectangularize strip shells

Naming
   Prefix / Suffix, Rename + Number, Find / Replace, Clean Names

LOD & Collision
   Auto LOD               ProOptimizer based, preserves borders / UVs / material IDs
   Collision Generator    Convex, Parts (for walls with openings), Box, Sphere
                          Unreal naming: UCX_ / UBX_ / USP_

TROUBLESHOOTING
---------------
- Open the MAXScript Listener (F11) to see error details.
- If packing says "falling back to box packer", the C# packer could not compile;
  details are written to MaxTools_diag.txt in this folder.
- Settings (window position, last page) are stored in <plugcfg>\MaxTools.ini.
