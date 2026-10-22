Based on tray_manager 0.2.3, retaining its MIT license.

Windows PopUpContextMenu uses TPM_RETURNCMD | TPM_NONOTIFY and sends the
selected command through the Flutter channel after the native popup loop
returns. It also posts WM_NULL as required by the Windows notification-area
menu pattern. Cancellation (zero) does not dispatch an action. This avoids
depending on WM_COMMAND routing through the Flutter window procedure when
the menu owner is minimized or hidden.

TPM_RIGHTBUTTON allows either mouse button to activate menu entries.
