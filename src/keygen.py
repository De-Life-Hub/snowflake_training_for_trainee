from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

# 秘密鍵の生成
private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
)

# 秘密鍵をファイルに保存（パスフレーズなし）
with open("rsa_key.p8", "wb") as f:
    f.write(private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ))

# 公開鍵をファイルに保存
with open("rsa_key.pub", "wb") as f:
    f.write(private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ))

print("キーペアの生成が完了しました")