Set the speed of every server fan through IPMI.

Usage:
  fan-speed <0-100>

Examples:
  fan-speed 30     Run all fans at 30%
  fan-speed 100    Run all fans at full speed

How it works:
  Switches the fan controller to manual mode, then applies the requested duty cycle to every fan. It uses Dell PowerEdge (iDRAC) raw IPMI commands, so other vendors need different raw codes.

  To return the fans to automatic control, run:
  sudo ipmitool raw 0x30 0x30 0x01 0x01

Permissions:
  Any member of the sudo, admin, or wheel group can run fan-speed without a password. The script re-runs itself through sudo, so there is no need to type sudo.

Setup:
  Installing fan-speed also installs ipmitool when it is missing and writes /etc/sudoers.d/mytool-fan-speed after validating it with visudo. Uninstalling removes that rule.
