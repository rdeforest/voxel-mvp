extends GutTest

# ConsoleCommands: every entry in the table registers with LimboConsole (and the two
# name-collision renames still register under their bare command strings). Collaborators
# can stay null here — register_all only binds the callables, it doesn't invoke them — so
# this guards the wiring (no missing method, no name drift) without a live world.

func test_every_command_registers_and_unregisters() -> void:
    var cc := ConsoleCommands.new()
    cc.register_all()
    for entry in cc._table():
        assert_true(LimboConsole.has_command(entry[1]), "registered: %s" % entry[1])
    # The set/get methods were renamed to dodge Object.set/get, but the command strings
    # the player types must be unchanged.
    assert_true(LimboConsole.has_command("set"), "set command present (set_uniform)")
    assert_true(LimboConsole.has_command("get"), "get command present (get_uniform)")
    cc.unregister_all()
    for entry in cc._table():
        assert_false(LimboConsole.has_command(entry[1]), "unregistered: %s" % entry[1])
