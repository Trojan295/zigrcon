# zigrcon

This is an implementation of the [Source RCON Protocol](https://developer.valvesoftware.com/wiki/Source_RCON_Protocol).
Done to give Zig a try.

## Usage

```bash
zig run main.zig -- address:port password
```

```bash
$ zig run main.zig -- localhost:25575 secret_password
Connected to localhost:25575
> time query day
The time is 77
> ^C

```
