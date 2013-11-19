module aes.encryptor;

import aes.common;
import aes.scheduler;

AesAlgorithm createEncryptor(const ubyte[] key) nothrow
in {
    auto keySize = key.length * 8;
    assert(keySize == 128 || keySize == 192 || keySize == 256);
}
body {
    version (X86_64) {
        import aes.aesni;
        
        if (aesniIsSupported()) {
            switch (key.length){
                case 16:
                    return new AesniEncryptor128(key);
                    break;
                case 24:
                    return new AesniEncryptor192(key);
                    break;
                case 32:
                    return new AesniEncryptor256(key);
                    break;
                default:
                    // can't happen if input contract is met
                    break;
            }
        }
    }
    
    return new DefaultEncryptor(key);
}

/// Encryptor written entirely in D code. Should be platform-independent.
class DefaultEncryptor : AesEncryptor {
    
    /**
     * Constructs an encryptor using the provided key.
     *
     * Throws: Exception if the key size is unsupported
     * Params:
     *     key = the encryption key. supported sizes are
     *           128, 192, and 256 bit keys.
     */
    this(const ubyte[] key) nothrow
    {
        roundKeys = scheduleKeys(key);
    }
    
    override void processBlock(ubyte[] block) nothrow
    {
        // copy the block into the state matrix
        state = *(cast(State*) block);
        auto nr = roundKeys.length - 1;
        
        addRoundKey(0);
        
        for (int i = 1; i < nr; i++) {
            
            subBytes();
            shiftRows();
            mixColumns();
            addRoundKey(i);
            
        }
        
        subBytes();
        shiftRows();
        addRoundKey(nr);
        
        // now copy the state matrix back into the original array
        *(cast(State*) block) = state;
    }
    
    override void processChunk(ubyte[] chunk) nothrow
    {
        while (chunk.length > 0) {
            processBlock(chunk[0 .. 16]);
            chunk = chunk[16 .. $];
        }
    }
    
    private State state;
    private State[] roundKeys;
    
    private void subBytes() nothrow
    {
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++)
                state[i][j] = sBox[state[i][j]];
    }
    
    private void shiftRows() nothrow
    {
        ubyte[4] t;
        
        for (int i = 1; i < 4; i++) {
            
            // copy row i into t
            for (int j = 0; j < 4; j++)
                t[j] = state[j][i];
            
            for (int j = 0; j < 4; j++)
                // note that & 3 is the same as % 4 for nonnegative numbers
                state[j][i] = t[(j + i) & 3];
        }
    }
    
    private void mixColumns() nothrow
    {
        ubyte[4] t;
        
        for (int i = 0; i < 4; i++) {
            
            // copy column i into t
            t[] = state[i];
            
            state[i][0] = mul2[t[0]] ^ mul3[t[1]] ^ t[2] ^ t[3];
            state[i][1] = mul2[t[1]] ^ mul3[t[2]] ^ t[3] ^ t[0];
            state[i][2] = mul2[t[2]] ^ mul3[t[3]] ^ t[0] ^ t[1];
            state[i][3] = mul2[t[3]] ^ mul3[t[0]] ^ t[1] ^ t[2];
        }
    }
    
    private void addRoundKey(size_t roundKeyIndex) nothrow
    {
        State key = roundKeys[roundKeyIndex];
        
        for (int i = 0; i < 4; i++)
            state[i][] ^= key[i][];
    }
}

// multiplication tables obtained from http://en.wikipedia.org/wiki/Rijndael_mix_columns

private immutable ubyte[] mul2 = [
    0x00,0x02,0x04,0x06,0x08,0x0a,0x0c,0x0e,0x10,0x12,0x14,0x16,0x18,0x1a,0x1c,0x1e,
    0x20,0x22,0x24,0x26,0x28,0x2a,0x2c,0x2e,0x30,0x32,0x34,0x36,0x38,0x3a,0x3c,0x3e,
    0x40,0x42,0x44,0x46,0x48,0x4a,0x4c,0x4e,0x50,0x52,0x54,0x56,0x58,0x5a,0x5c,0x5e,
    0x60,0x62,0x64,0x66,0x68,0x6a,0x6c,0x6e,0x70,0x72,0x74,0x76,0x78,0x7a,0x7c,0x7e,
    0x80,0x82,0x84,0x86,0x88,0x8a,0x8c,0x8e,0x90,0x92,0x94,0x96,0x98,0x9a,0x9c,0x9e,
    0xa0,0xa2,0xa4,0xa6,0xa8,0xaa,0xac,0xae,0xb0,0xb2,0xb4,0xb6,0xb8,0xba,0xbc,0xbe,
    0xc0,0xc2,0xc4,0xc6,0xc8,0xca,0xcc,0xce,0xd0,0xd2,0xd4,0xd6,0xd8,0xda,0xdc,0xde,
    0xe0,0xe2,0xe4,0xe6,0xe8,0xea,0xec,0xee,0xf0,0xf2,0xf4,0xf6,0xf8,0xfa,0xfc,0xfe,
    0x1b,0x19,0x1f,0x1d,0x13,0x11,0x17,0x15,0x0b,0x09,0x0f,0x0d,0x03,0x01,0x07,0x05,
    0x3b,0x39,0x3f,0x3d,0x33,0x31,0x37,0x35,0x2b,0x29,0x2f,0x2d,0x23,0x21,0x27,0x25,
    0x5b,0x59,0x5f,0x5d,0x53,0x51,0x57,0x55,0x4b,0x49,0x4f,0x4d,0x43,0x41,0x47,0x45,
    0x7b,0x79,0x7f,0x7d,0x73,0x71,0x77,0x75,0x6b,0x69,0x6f,0x6d,0x63,0x61,0x67,0x65,
    0x9b,0x99,0x9f,0x9d,0x93,0x91,0x97,0x95,0x8b,0x89,0x8f,0x8d,0x83,0x81,0x87,0x85,
    0xbb,0xb9,0xbf,0xbd,0xb3,0xb1,0xb7,0xb5,0xab,0xa9,0xaf,0xad,0xa3,0xa1,0xa7,0xa5,
    0xdb,0xd9,0xdf,0xdd,0xd3,0xd1,0xd7,0xd5,0xcb,0xc9,0xcf,0xcd,0xc3,0xc1,0xc7,0xc5,
    0xfb,0xf9,0xff,0xfd,0xf3,0xf1,0xf7,0xf5,0xeb,0xe9,0xef,0xed,0xe3,0xe1,0xe7,0xe5
];

private immutable ubyte[] mul3 = [
    0x00,0x03,0x06,0x05,0x0c,0x0f,0x0a,0x09,0x18,0x1b,0x1e,0x1d,0x14,0x17,0x12,0x11,
    0x30,0x33,0x36,0x35,0x3c,0x3f,0x3a,0x39,0x28,0x2b,0x2e,0x2d,0x24,0x27,0x22,0x21,
    0x60,0x63,0x66,0x65,0x6c,0x6f,0x6a,0x69,0x78,0x7b,0x7e,0x7d,0x74,0x77,0x72,0x71,
    0x50,0x53,0x56,0x55,0x5c,0x5f,0x5a,0x59,0x48,0x4b,0x4e,0x4d,0x44,0x47,0x42,0x41,
    0xc0,0xc3,0xc6,0xc5,0xcc,0xcf,0xca,0xc9,0xd8,0xdb,0xde,0xdd,0xd4,0xd7,0xd2,0xd1,
    0xf0,0xf3,0xf6,0xf5,0xfc,0xff,0xfa,0xf9,0xe8,0xeb,0xee,0xed,0xe4,0xe7,0xe2,0xe1,
    0xa0,0xa3,0xa6,0xa5,0xac,0xaf,0xaa,0xa9,0xb8,0xbb,0xbe,0xbd,0xb4,0xb7,0xb2,0xb1,
    0x90,0x93,0x96,0x95,0x9c,0x9f,0x9a,0x99,0x88,0x8b,0x8e,0x8d,0x84,0x87,0x82,0x81,
    0x9b,0x98,0x9d,0x9e,0x97,0x94,0x91,0x92,0x83,0x80,0x85,0x86,0x8f,0x8c,0x89,0x8a,
    0xab,0xa8,0xad,0xae,0xa7,0xa4,0xa1,0xa2,0xb3,0xb0,0xb5,0xb6,0xbf,0xbc,0xb9,0xba,
    0xfb,0xf8,0xfd,0xfe,0xf7,0xf4,0xf1,0xf2,0xe3,0xe0,0xe5,0xe6,0xef,0xec,0xe9,0xea,
    0xcb,0xc8,0xcd,0xce,0xc7,0xc4,0xc1,0xc2,0xd3,0xd0,0xd5,0xd6,0xdf,0xdc,0xd9,0xda,
    0x5b,0x58,0x5d,0x5e,0x57,0x54,0x51,0x52,0x43,0x40,0x45,0x46,0x4f,0x4c,0x49,0x4a,
    0x6b,0x68,0x6d,0x6e,0x67,0x64,0x61,0x62,0x73,0x70,0x75,0x76,0x7f,0x7c,0x79,0x7a,
    0x3b,0x38,0x3d,0x3e,0x37,0x34,0x31,0x32,0x23,0x20,0x25,0x26,0x2f,0x2c,0x29,0x2a,
    0x0b,0x08,0x0d,0x0e,0x07,0x04,0x01,0x02,0x13,0x10,0x15,0x16,0x1f,0x1c,0x19,0x1a
];

// a simple test of encryption using examples from
// appendix C of the AES spec in the FIPS-197 document.
// only tests DefaultEncryptor, AES-NI tests are in aesni.d.
unittest {
    
    immutable ubyte[] plaintext = [
        0x00,0x11,0x22,0x33,
        0x44,0x55,0x66,0x77,
        0x88,0x99,0xaa,0xbb,
        0xcc,0xdd,0xee,0xff
    ];
    
    ubyte[] buf = new ubyte[16];
    AesAlgorithm e;
    
    ubyte[] key128 = [
        0x00,0x01,0x02,0x03,
        0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b,
        0x0c,0x0d,0x0e,0x0f
    ];
    
    ubyte[] ciphertext128 = [
        0x69,0xc4,0xe0,0xd8,
        0x6a,0x7b,0x04,0x30,
        0xd8,0xcd,0xb7,0x80,
        0x70,0xb4,0xc5,0x5a
    ];
    
    e = new DefaultEncryptor(key128);
    buf[] = plaintext[];
    e.processBlock(buf);
    assert(buf == ciphertext128);
    
    ubyte[] key192 = [
        0x00,0x01,0x02,0x03,0x04,0x05,
        0x06,0x07,0x08,0x09,0x0a,0x0b,
        0x0c,0x0d,0x0e,0x0f,0x10,0x11,
        0x12,0x13,0x14,0x15,0x16,0x17
    ];
    
    ubyte[] ciphertext192 = [
        0xdd,0xa9,0x7c,0xa4,
        0x86,0x4c,0xdf,0xe0,
        0x6e,0xaf,0x70,0xa0,
        0xec,0x0d,0x71,0x91
    ];
    
    e = new DefaultEncryptor(key192);
    buf[] = plaintext[];
    e.processBlock(buf);
    assert(buf == ciphertext192);
    
    ubyte[] key256 = [
        0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,
        0x08,0x09,0x0a,0x0b,0x0c,0x0d,0x0e,0x0f,
        0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,
        0x18,0x19,0x1a,0x1b,0x1c,0x1d,0x1e,0x1f
    ];
    
    ubyte[] ciphertext256 = [
        0x8e,0xa2,0xb7,0xca,
        0x51,0x67,0x45,0xbf,
        0xea,0xfc,0x49,0x90,
        0x4b,0x49,0x60,0x89
    ];
    
    e = new DefaultEncryptor(key256);
    buf[] = plaintext[];
    e.processBlock(buf);
    assert(buf == ciphertext256);
}