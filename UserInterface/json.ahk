#Requires AutoHotkey v2.0

HM_JsonParse(text) {
    parser := HMJsonParser(text)
    return parser.Parse()
}

HM_JsonStringify(value) {
    valueType := Type(value)
    if (valueType = "Map") {
        parts := []
        for key, item in value
            parts.Push(HM_JsonQuote(key) ":" HM_JsonStringify(item))
        return "{" HM_Join(parts, ",") "}"
    }
    if (valueType = "Array") {
        parts := []
        for item in value
            parts.Push(HM_JsonStringify(item))
        return "[" HM_Join(parts, ",") "]"
    }
    if (valueType = "String")
        return HM_JsonQuote(value)
    if (valueType = "Integer" || valueType = "Float")
        return IsNumber(value) ? value "" : "null"
    if (value = "")
        return '""'
    return "null"
}

HM_JsonQuote(value) {
    value := StrReplace(value, "\", "\\")
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, "`b", "\b")
    value := StrReplace(value, "`f", "\f")
    value := StrReplace(value, "`n", "\n")
    value := StrReplace(value, "`r", "\r")
    value := StrReplace(value, "`t", "\t")
    return '"' value '"'
}

HM_Join(values, separator := "") {
    result := ""
    for index, value in values {
        if (index > 1)
            result .= separator
        result .= value
    }
    return result
}

class HMJsonParser {
    __New(text) {
        this.text := text
        this.position := 1
        this.length := StrLen(text)
    }

    Parse() {
        this.SkipWhitespace()
        value := this.ReadValue()
        this.SkipWhitespace()
        if (this.position <= this.length)
            throw Error("Unexpected data after JSON value.")
        return value
    }

    ReadValue() {
        this.SkipWhitespace()
        char := SubStr(this.text, this.position, 1)
        if (char = "{")
            return this.ReadObject()
        if (char = "[")
            return this.ReadArray()
        if (char = '"')
            return this.ReadString()
        if (char = "t") {
            this.ExpectWord("true")
            return 1
        }
        if (char = "f") {
            this.ExpectWord("false")
            return 0
        }
        if (char = "n") {
            this.ExpectWord("null")
            return ""
        }
        return this.ReadNumber()
    }

    ReadObject() {
        object := Map()
        this.position += 1
        this.SkipWhitespace()
        if (this.Take("}"))
            return object

        loop {
            this.SkipWhitespace()
            if (SubStr(this.text, this.position, 1) != '"')
                throw Error("Expected a JSON object key.")
            key := this.ReadString()
            this.SkipWhitespace()
            this.Expect(":")
            object[key] := this.ReadValue()
            this.SkipWhitespace()
            if (this.Take("}"))
                return object
            this.Expect(",")
        }
    }

    ReadArray() {
        array := []
        this.position += 1
        this.SkipWhitespace()
        if (this.Take("]"))
            return array

        loop {
            array.Push(this.ReadValue())
            this.SkipWhitespace()
            if (this.Take("]"))
                return array
            this.Expect(",")
        }
    }

    ReadString() {
        this.Expect('"')
        result := ""
        while (this.position <= this.length) {
            char := SubStr(this.text, this.position, 1)
            this.position += 1
            if (char = '"')
                return result
            if (char != "\") {
                result .= char
                continue
            }

            if (this.position > this.length)
                throw Error("Incomplete JSON escape.")
            escape := SubStr(this.text, this.position, 1)
            this.position += 1
            switch escape {
                case '"': result .= '"'
                case "\": result .= "\"
                case "/": result .= "/"
                case "b": result .= Chr(8)
                case "f": result .= Chr(12)
                case "n": result .= "`n"
                case "r": result .= "`r"
                case "t": result .= "`t"
                case "u": result .= Chr(this.ReadHexCodeUnit())
                default: throw Error("Invalid JSON escape.")
            }
        }
        throw Error("Unterminated JSON string.")
    }

    ReadHexCodeUnit() {
        hex := SubStr(this.text, this.position, 4)
        if (StrLen(hex) != 4 || !RegExMatch(hex, "i)^[0-9a-f]{4}$"))
            throw Error("Invalid Unicode escape.")
        this.position += 4
        return ("0x" hex) + 0
    }

    ReadNumber() {
        remaining := SubStr(this.text, this.position)
        if !RegExMatch(remaining, "^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?", &match)
            throw Error("Invalid JSON value.")
        this.position += StrLen(match[0])
        return match[0] + 0
    }

    ExpectWord(word) {
        if (SubStr(this.text, this.position, StrLen(word)) != word)
            throw Error("Invalid JSON literal.")
        this.position += StrLen(word)
    }

    Expect(char) {
        if !this.Take(char)
            throw Error("Expected '" char "' in JSON.")
    }

    Take(char) {
        if (SubStr(this.text, this.position, 1) != char)
            return false
        this.position += 1
        return true
    }

    SkipWhitespace() {
        while (this.position <= this.length) {
            char := SubStr(this.text, this.position, 1)
            if (char != " " && char != "`t" && char != "`r" && char != "`n")
                return
            this.position += 1
        }
    }
}
