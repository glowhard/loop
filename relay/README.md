# The relay

Lets a browser anywhere reach a PC that is not on the internet. It passes bytes
between the two and holds nothing: no sessions, no files, no conversation.

On the server:

    sudo cp loop-relay.service /etc/systemd/system/
    sudo systemctl enable --now loop-relay

It reads `/etc/loop-relay.json`, which lists the fingerprint of each machine
allowed to register:

    { "machines": ["<sha256 of that PC's machine token>"] }

Loop makes the token, keeps it, and sends only its fingerprint here. The key a
browser needs is never stored on this server either — only its fingerprint,
handed over by the PC when it registers.
