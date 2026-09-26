extends RefCounted

# Tab-separated rows for the single-voxel probe's output files (scripts/dev/summarize_single_voxel.py
# reads them). Floats are written to 4 places; a missing key is an empty field.


static func line(row: Dictionary, columns: Array) -> String:
    var out := PackedStringArray()
    for k in columns:
        var v: Variant = row.get(k, "")
        out.append("%.4f" % v if v is float else str(v))
    return "\t".join(out)


static func write(path: String, table: Array[Dictionary], columns: Array) -> void:
    var f := FileAccess.open(path, FileAccess.WRITE)
    f.store_line("\t".join(columns))
    for row in table:
        f.store_line(line(row, columns))
