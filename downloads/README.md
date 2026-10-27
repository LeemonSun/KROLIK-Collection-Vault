# Private preview payloads

Official unmodified OFL font and locally exported Windows preview ZIP, split to stay below connector payload limits. Not model weights. SHA-256 and assembly order: preview-manifest.json. START_WINDOWS.cmd reconstructs and verifies both packages, extracts the existing ZIP and launches the preview without compiling or downloading anything. Developer restore: python tools/restore_packages.py.

The direct unsegmented Windows ZIP is also delivered in the chat. GitHub remains storage only, no Actions or hosted tasks.
