.macro SpriteLine(str) {
    .errorif (str.size() != 24), "unexpected string length, should be 24."
    .var str1 = str.substring(0, 8)    
    .var str2 = str.substring(8, 16)
    .var str3 = str.substring(16, 24)

    .byte StringToBinary(str1) , StringToBinary(str2), StringToBinary(str3)
}

.function StringToBinary(str) {
    .var exponent = 0
    .var result = 0;
    .for (var i = str.size()- 1 ; i >= 0 ; i--) {
        .if (str.charAt(i) == "#") {
            .eval result = result + pow(2, exponent);
        } else {
            .errorif str.charAt(i) != ".", "Only use . for 0 and # for 1"            
        }
        .eval exponent = exponent + 1
    }

    .return result
}