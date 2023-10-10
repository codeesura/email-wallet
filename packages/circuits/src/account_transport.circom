
pragma circom 2.1.5;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/poseidon.circom";
include "@zk-email/circuits/email-verifier.circom";
include "@zk-email/circuits/helpers/extract.circom";
include "./utils/constants.circom";
include "./utils/email_addr_pointer.circom";
include "./utils/account_key_commit.circom";
include "./utils/wallet_salt.circom";
include "./utils/hex2int.circom";
include "./utils/bytes2ints.circom";
include "./utils/hash_sign.circom";
include "./utils/email_nullifier.circom";
include "./utils/digit2int.circom";
include "@zk-email/zk-regex-circom/circuits/common/from_addr_regex.circom";
include "@zk-email/zk-regex-circom/circuits/common/email_domain_regex.circom";
include "./regexes/invitation_code_regex.circom";
include "@zk-email/zk-regex-circom/circuits/common/timestamp_regex.circom";


// Here, n and k are the biginteger parameters for RSA
// This is because the number is chunked into k pack_size of n bits each
template AccountTransport(n, k, max_header_bytes) {
    signal input in_padded[max_header_bytes]; // prehashed email data, includes up to 512 + 64? bytes of padding pre SHA256, and padded with lots of 0s at end after the length
    signal input pubkey[k]; // rsa pubkey, verified with smart contract + DNSSEC proof. split up into k parts of n bits each.
    signal input signature[k]; // rsa signature. split up into k parts of n bits each.
    signal input in_padded_len; // length of in email data including the padding, which will inform the sha256 block length
    signal input old_relayer_rand_hash;
    signal input new_relayer_rand;
    signal input sender_email_idx; // index of the from email address (= sender email address) in the header
    signal input code_idx; // index of the invitation code in the header
    signal input domain_idx;
    signal input timestamp_idx;

    var email_max_bytes = email_max_bytes_const();
    var domain_len = domain_len_const();
    var domain_filed_len = compute_ints_size(domain_len);
    var code_len = invitation_code_len_const();
    var timestamp_len = timestamp_len_const();

    signal output domain_name[domain_filed_len];
    signal output pubkey_hash;
    signal output email_nullifier;
    signal output old_ak_commit;
    signal output new_ak_commit;
    signal output new_relayer_rand_hash;
    signal output timestamp;
    
    
    component email_verifier = EmailVerifier(max_header_bytes, 0, n, k, 1);
    email_verifier.in_padded <== in_padded;
    email_verifier.pubkey <== pubkey;
    email_verifier.signature <== signature;
    email_verifier.in_len_padded_bytes <== in_padded_len;
    signal header_hash[256] <== email_verifier.sha;
    pubkey_hash <== email_verifier.pubkey_hash;

    // FROM HEADER REGEX
    signal from_regex_out, from_regex_reveal[max_header_bytes];
    (from_regex_out, from_regex_reveal) <== FromAddrRegex(max_header_bytes)(in_padded);
    from_regex_out === 1;
    signal sender_email_addr[email_max_bytes];
    sender_email_addr <== VarShiftLeft(max_header_bytes, email_max_bytes)(from_regex_reveal, sender_email_idx);

    // INVITATION CODE REGEX
    signal code_regex_out, code_regex_reveal[max_header_bytes];
    (code_regex_out, code_regex_reveal) <== InvitationCodeRegex(max_header_bytes)(in_padded);
    code_regex_out === 1;
    signal invitation_code_hex[code_len] <== VarShiftLeft(max_header_bytes, code_len)(code_regex_reveal, code_idx);
    signal sender_ak <== Hex2Field()(invitation_code_hex);

    // DOMAIN NAME HEADER REGEX
    signal domain_regex_out, domain_regex_reveal[email_max_bytes];
    (domain_regex_out, domain_regex_reveal) <== EmailDomainRegex(email_max_bytes)(sender_email_addr);
    domain_regex_out === 1;
    signal domain_name_bytes[domain_len];
    domain_name_bytes <== VarShiftLeft(email_max_bytes, domain_len)(domain_regex_reveal, domain_idx);
    domain_name <== Bytes2Ints(domain_len)(domain_name_bytes);

    signal sign_hash;
    (sign_hash, _) <== HashSign(n,k)(signature);
    email_nullifier <== EmailNullifier()(sign_hash);

    var num_email_addr_ints = compute_ints_size(email_max_bytes);
    signal sender_email_addr_ints[num_email_addr_ints] <== Bytes2Ints(email_max_bytes)(sender_email_addr);
    old_ak_commit <== AccountKeyCommit(num_email_addr_ints)(sender_ak, sender_email_addr_ints, old_relayer_rand_hash);
    new_relayer_rand_hash <== Poseidon(1)([new_relayer_rand]);
    new_ak_commit <== AccountKeyCommit(num_email_addr_ints)(sender_ak, sender_email_addr_ints, new_relayer_rand_hash);


    // TIMESTAMP REGEX
    signal timestamp_regex_out, timestamp_regex_reveal[max_header_bytes];
    (timestamp_regex_out, timestamp_regex_reveal) <== TimestampRegex(max_header_bytes)(in_padded);
    timestamp_regex_out === 1;
    signal timestamp_str[timestamp_len];
    timestamp_str <== VarShiftLeft(max_header_bytes, timestamp_len)(timestamp_regex_reveal, timestamp_idx);
    timestamp <== Digit2Int(timestamp_len)(timestamp_str);
}

// Args:
// * n = 121 is the number of bits in each chunk of the modulus (RSA parameter)
// * k = 17 is the number of chunks in the modulus (RSA parameter)
// * max_header_bytes = 1024 is the max number of bytes in the header
component main { public [old_relayer_rand_hash] }  = AccountTransport(121, 17, 1024);
