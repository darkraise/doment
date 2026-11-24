// Inline MSBuild task that reads a portable project's output assembly for native-code findings (DOMENT033).
// The factory compiles against netstandard 2.0 and cannot reference System.Reflection.Metadata (probe P3 in
// docs/dforge/research/2026-11-24-build-probes.md), so this file reads the ECMA-335 metadata tables itself.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using Microsoft.Build.Framework;
using Microsoft.Build.Utilities;

public class DomentPortableAssemblyCheck : Task
{
    [Required]
    public string AssemblyPath { get; set; }

    [Required]
    public string ProjectName { get; set; }

    public override bool Execute()
    {
        List<string> findings;
        try
        {
            findings = new DomentMetadataReader(File.ReadAllBytes(AssemblyPath)).PortableFindings();
        }
        catch (Exception e) when (e is IOException || e is UnauthorizedAccessException || e is InvalidDataException)
        {
            Log.LogError("cannot read the metadata of {0}: {1}", AssemblyPath, e.Message);
            return false;
        }

        foreach (string finding in findings)
        {
            Log.LogError(null, "DOMENT033", null, null, 0, 0, 0, 0, "{0} is portable but {1}", ProjectName, finding);
        }

        return !Log.HasLoggedErrors;
    }
}

internal sealed class DomentMetadataReader
{
    private const int TableCount = 0x2D;
    private const int TypeRef = 0x01, TypeDef = 0x02, Field = 0x04, MethodDef = 0x06, MemberRef = 0x0A;
    private const int CustomAttribute = 0x0C, ModuleRef = 0x1A, ImplMap = 0x1C;

    // Column kinds: a positive number is a fixed width; S, G and B are heap indexes; Ix | t indexes table t;
    // Cx | c is coded index kind c of Coded.
    private const int S = -1, G = -2, B = -3, Ix = 0x100, Cx = 0x200;

    private const int TypeDefOrRef = Cx | 0, HasConstant = Cx | 1, HasCustomAttribute = Cx | 2, HasFieldMarshal = Cx | 3;
    private const int HasDeclSecurity = Cx | 4, MemberRefParent = Cx | 5, HasSemantics = Cx | 6, MethodDefOrRef = Cx | 7;
    private const int MemberForwarded = Cx | 8, Implementation = Cx | 9, CustomAttributeType = Cx | 10;
    private const int ResolutionScope = Cx | 11, TypeOrMethodDef = Cx | 12;

    // ECMA-335 II.24.2.6: the tag width, then the table each tag value names (-1 for an unused tag).
    private static readonly int[][] Coded =
    {
        new[] { 2, 0x02, 0x01, 0x1B },
        new[] { 2, 0x04, 0x08, 0x17 },
        new[] { 5, 0x06, 0x04, 0x01, 0x02, 0x08, 0x09, 0x0A, 0x00, 0x0E, 0x17, 0x14, 0x11, 0x1A, 0x1B, 0x20, 0x23, 0x26, 0x27, 0x28, 0x2A, 0x2C, 0x2B },
        new[] { 1, 0x04, 0x08 },
        new[] { 2, 0x02, 0x06, 0x20 },
        new[] { 3, 0x02, 0x01, 0x1A, 0x06, 0x1B },
        new[] { 1, 0x14, 0x17 },
        new[] { 1, 0x06, 0x0A },
        new[] { 1, 0x04, 0x06 },
        new[] { 2, 0x26, 0x23, 0x27 },
        new[] { 3, -1, -1, 0x06, 0x0A, -1 },
        new[] { 2, 0x00, 0x1A, 0x23, 0x01 },
        new[] { 1, 0x02, 0x06 },
    };

    // ECMA-335 II.22, tables 0x00 to 0x2C in order.
    private static readonly int[][] Schema =
    {
        new[] { 2, S, G, G, G },
        new[] { ResolutionScope, S, S },
        new[] { 4, S, S, TypeDefOrRef, Ix | 0x04, Ix | 0x06 },
        new[] { Ix | 0x04 },
        new[] { 2, S, B },
        new[] { Ix | 0x06 },
        new[] { 4, 2, 2, S, B, Ix | 0x08 },
        new[] { Ix | 0x08 },
        new[] { 2, 2, S },
        new[] { Ix | 0x02, TypeDefOrRef },
        new[] { MemberRefParent, S, B },
        new[] { 2, HasConstant, B },
        new[] { HasCustomAttribute, CustomAttributeType, B },
        new[] { HasFieldMarshal, B },
        new[] { 2, HasDeclSecurity, B },
        new[] { 2, 4, Ix | 0x02 },
        new[] { 4, Ix | 0x04 },
        new[] { B },
        new[] { Ix | 0x02, Ix | 0x14 },
        new[] { Ix | 0x14 },
        new[] { 2, S, TypeDefOrRef },
        new[] { Ix | 0x02, Ix | 0x17 },
        new[] { Ix | 0x17 },
        new[] { 2, S, B },
        new[] { 2, Ix | 0x06, HasSemantics },
        new[] { Ix | 0x02, MethodDefOrRef, MethodDefOrRef },
        new[] { S },
        new[] { B },
        new[] { 2, MemberForwarded, S, Ix | 0x1A },
        new[] { 4, Ix | 0x04 },
        new[] { 4, 4 },
        new[] { 4 },
        new[] { 4, 2, 2, 2, 2, 4, B, S, S },
        new[] { 4 },
        new[] { 4, 4, 4 },
        new[] { 2, 2, 2, 2, 4, B, S, S, B },
        new[] { 4, Ix | 0x23 },
        new[] { 4, 4, 4, Ix | 0x23 },
        new[] { 4, S, B },
        new[] { 4, 4, S, S, Implementation },
        new[] { 4, 4, S, Implementation },
        new[] { Ix | 0x02, Ix | 0x02 },
        new[] { 2, 2, TypeOrMethodDef, S },
        new[] { MethodDefOrRef, B },
        new[] { Ix | 0x2A, TypeDefOrRef },
    };

    private readonly byte[] data;
    private readonly int[] rows = new int[TableCount];
    private readonly int[] tableStart = new int[TableCount];
    private readonly int[] rowWidth = new int[TableCount];
    private readonly int[][] columnOffset = new int[TableCount][];
    private readonly int[][] columnWidth = new int[TableCount][];
    private int strings, stringsEnd, blob, blobEnd;
    private int stringIndex, guidIndex, blobIndex;

    public DomentMetadataReader(byte[] data)
    {
        this.data = data;
        Parse();
    }

    public List<string> PortableFindings()
    {
        var findings = new List<string>();

        for (int r = 1; r <= rows[ImplMap]; r++)
        {
            int forwarded = Cell(ImplMap, r, 1);
            int index = forwarded >> 1;
            string member = (forwarded & 1) == 1
                ? TypeName(Owner(5, index)) + "." + HeapString(Cell(MethodDef, index, 3))
                : TypeName(Owner(4, index)) + "." + HeapString(Cell(Field, index, 1));
            string library = HeapString(Cell(ModuleRef, Cell(ImplMap, r, 3), 0));
            findings.Add("declares a native import " + member + " from " + library);
        }

        for (int r = 1; r <= rows[TypeRef]; r++)
        {
            if (HeapString(Cell(TypeRef, r, 2)) == "System.Runtime.InteropServices" && HeapString(Cell(TypeRef, r, 1)) == "NativeLibrary")
            {
                findings.Add("references System.Runtime.InteropServices.NativeLibrary");
                break;
            }
        }

        for (int r = 1; r <= rows[CustomAttribute]; r++)
        {
            // Tag 14 of HasCustomAttribute is the Assembly table.
            if ((Cell(CustomAttribute, r, 0) & 0x1F) != 14)
            {
                continue;
            }

            if (AttributeType(Cell(CustomAttribute, r, 1)) == "System.Runtime.Versioning.SupportedOSPlatformAttribute")
            {
                findings.Add("carries the assembly attribute SupportedOSPlatform(\"" + FirstStringArgument(Cell(CustomAttribute, r, 2)) + "\")");
            }
        }

        return findings;
    }

    private void Parse()
    {
        int pe = U32(0x3C);
        if (U32(pe) != 0x00004550)
        {
            throw new InvalidDataException("no PE signature");
        }

        int sectionCount = U16(pe + 6);
        int optional = pe + 24;
        int magic = U16(optional);
        int directories = magic == 0x20B ? optional + 112 : magic == 0x10B ? optional + 96 : throw new InvalidDataException("unknown optional header");
        int sections = optional + U16(pe + 20);
        int cli = FileOffset(U32(directories + 14 * 8), sections, sectionCount);
        int metadata = FileOffset(U32(cli + 8), sections, sectionCount);
        if (U32(metadata) != 0x424A5342)
        {
            throw new InvalidDataException("no metadata signature");
        }

        int p = metadata + 16 + U32(metadata + 12);
        int streamCount = U16(p + 2);
        p += 4;
        int tables = -1;
        for (int i = 0; i < streamCount; i++)
        {
            int offset = metadata + U32(p);
            int size = U32(p + 4);
            int nameStart = p + 8;
            int nameEnd = nameStart;
            while (Byte(nameEnd) != 0)
            {
                nameEnd++;
            }

            string name = Encoding.ASCII.GetString(data, nameStart, nameEnd - nameStart);
            p = nameStart + ((nameEnd - nameStart + 4) & ~3);
            if (name == "#~" || name == "#-")
            {
                tables = offset;
            }
            else if (name == "#Strings")
            {
                strings = offset;
                stringsEnd = offset + size;
            }
            else if (name == "#Blob")
            {
                blob = offset;
                blobEnd = offset + size;
            }
        }

        if (tables < 0)
        {
            throw new InvalidDataException("no metadata tables stream");
        }

        int heapSizes = Byte(tables + 6);
        stringIndex = (heapSizes & 0x01) != 0 ? 4 : 2;
        guidIndex = (heapSizes & 0x02) != 0 ? 4 : 2;
        blobIndex = (heapSizes & 0x04) != 0 ? 4 : 2;
        ulong valid = (uint)U32(tables + 8) | ((ulong)(uint)U32(tables + 12) << 32);
        int q = tables + 24;
        for (int t = 0; t < 64; t++)
        {
            if ((valid & (1UL << t)) == 0)
            {
                continue;
            }

            // Tables past 0x2C belong to portable PDBs; their rows follow every table read here.
            if (t < TableCount)
            {
                rows[t] = U32(q);
            }

            q += 4;
        }

        if ((heapSizes & 0x40) != 0)
        {
            q += 4;
        }

        for (int t = 0; t < TableCount; t++)
        {
            int[] columns = Schema[t];
            columnOffset[t] = new int[columns.Length];
            columnWidth[t] = new int[columns.Length];
            int width = 0;
            for (int c = 0; c < columns.Length; c++)
            {
                columnOffset[t][c] = width;
                columnWidth[t][c] = ColumnWidth(columns[c]);
                width += columnWidth[t][c];
            }

            rowWidth[t] = width;
            tableStart[t] = q;
            q += rows[t] * width;
        }
    }

    private int ColumnWidth(int kind)
    {
        if (kind == S)
        {
            return stringIndex;
        }

        if (kind == G)
        {
            return guidIndex;
        }

        if (kind == B)
        {
            return blobIndex;
        }

        if ((kind & Cx) != 0)
        {
            int[] coded = Coded[kind & 0xFF];
            int most = 0;
            for (int i = 1; i < coded.Length; i++)
            {
                if (coded[i] >= 0)
                {
                    most = Math.Max(most, rows[coded[i]]);
                }
            }

            return most < (1 << (16 - coded[0])) ? 2 : 4;
        }

        if ((kind & Ix) != 0)
        {
            return rows[kind & 0xFF] < 0x10000 ? 2 : 4;
        }

        return kind;
    }

    private int Cell(int table, int row, int column)
    {
        if (row < 1 || row > rows[table])
        {
            throw new InvalidDataException("row " + row + " of table " + table + " is out of range");
        }

        int at = tableStart[table] + (row - 1) * rowWidth[table] + columnOffset[table][column];
        return columnWidth[table][column] == 4 ? U32(at) : U16(at);
    }

    // The TypeDef whose field list (column 4) or method list (column 5) holds the row: the last type whose list
    // starts at or before it.
    private int Owner(int listColumn, int row)
    {
        int owner = 0;
        for (int t = 1; t <= rows[TypeDef]; t++)
        {
            if (Cell(TypeDef, t, listColumn) <= row)
            {
                owner = t;
            }
        }

        if (owner == 0)
        {
            throw new InvalidDataException("no type owns row " + row);
        }

        return owner;
    }

    private string TypeName(int typeDef)
    {
        return HeapString(Cell(TypeDef, typeDef, 1));
    }

    private string QualifiedName(int nameIndex, int namespaceIndex)
    {
        string ns = HeapString(namespaceIndex);
        return ns.Length == 0 ? HeapString(nameIndex) : ns + "." + HeapString(nameIndex);
    }

    // The full name of an attribute's type from its CustomAttributeType constructor, or null.
    private string AttributeType(int constructor)
    {
        int index = constructor >> 3;
        switch (constructor & 0x07)
        {
            case 2:
                int owner = Owner(5, index);
                return QualifiedName(Cell(TypeDef, owner, 1), Cell(TypeDef, owner, 2));
            case 3:
                int parent = Cell(MemberRef, index, 0);
                int type = parent >> 3;
                switch (parent & 0x07)
                {
                    case 0:
                        return QualifiedName(Cell(TypeDef, type, 1), Cell(TypeDef, type, 2));
                    case 1:
                        return QualifiedName(Cell(TypeRef, type, 1), Cell(TypeRef, type, 2));
                    default:
                        return null;
                }
            default:
                return null;
        }
    }

    // ECMA-335 II.23.3: a custom attribute blob is the prolog 0x0001 and then the fixed arguments; a string
    // argument is a SerString, 0xFF for null.
    private string FirstStringArgument(int blobOffset)
    {
        int p = blob + blobOffset;
        int length = CompressedLength(ref p);
        int end = p + length;
        if (end > blobEnd || length < 3 || U16(p) != 0x0001)
        {
            throw new InvalidDataException("malformed custom attribute blob");
        }

        p += 2;
        if (Byte(p) == 0xFF)
        {
            return "null";
        }

        int count = CompressedLength(ref p);
        if (p + count > end)
        {
            throw new InvalidDataException("malformed custom attribute string");
        }

        return Encoding.UTF8.GetString(data, p, count);
    }

    private int CompressedLength(ref int p)
    {
        int first = Byte(p);
        if ((first & 0x80) == 0)
        {
            p += 1;
            return first;
        }

        if ((first & 0xC0) == 0x80)
        {
            int value = ((first & 0x3F) << 8) | Byte(p + 1);
            p += 2;
            return value;
        }

        int wide = ((first & 0x1F) << 24) | (Byte(p + 1) << 16) | (Byte(p + 2) << 8) | Byte(p + 3);
        p += 4;
        return wide;
    }

    private string HeapString(int index)
    {
        int start = strings + index;
        int end = start;
        while (end < stringsEnd && Byte(end) != 0)
        {
            end++;
        }

        if (end >= stringsEnd)
        {
            throw new InvalidDataException("string index " + index + " is out of range");
        }

        return Encoding.UTF8.GetString(data, start, end - start);
    }

    // PE section headers are 40 bytes: virtual size at 8, virtual address at 12, raw size at 16, raw pointer at 20.
    private int FileOffset(int rva, int sections, int count)
    {
        for (int i = 0; i < count; i++)
        {
            int header = sections + i * 40;
            int virtualAddress = U32(header + 12);
            int size = Math.Max(U32(header + 8), U32(header + 16));
            if (rva >= virtualAddress && rva < virtualAddress + size)
            {
                return rva - virtualAddress + U32(header + 20);
            }
        }

        throw new InvalidDataException("RVA " + rva + " lies in no section");
    }

    private int Byte(int at)
    {
        if (at < 0 || at >= data.Length)
        {
            throw new InvalidDataException("offset " + at + " is past the end of the file");
        }

        return data[at];
    }

    private int U16(int at)
    {
        return Byte(at) | (Byte(at + 1) << 8);
    }

    private int U32(int at)
    {
        return U16(at) | (U16(at + 2) << 16);
    }
}
