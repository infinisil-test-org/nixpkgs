{ buildGoModule, fetchFromGitHub, fetchpatch }:
buildGoModule {
  name = "codeowners-validator";
  src = fetchFromGitHub {
    owner = "mszostok";
    repo = "codeowners-validator";
    rev = "f3651e3810802a37bd965e6a9a7210728179d076";
    hash = "sha256-5aSmmRTsOuPcVLWfDF6EBz+6+/Qpbj66udAmi1CLmWQ=";
  };
  patches = [
    # https://github.com/mszostok/codeowners-validator/pull/222
    (fetchpatch {
      name = "user-write-access-check";
      url = "https://github.com/mszostok/codeowners-validator/compare/f3651e3810802a37bd965e6a9a7210728179d076...840eeb88b4da92bda3e13c838f67f6540b9e8529.patch";
      hash = "sha256-t3Dtt8SP9nbO3gBrM0nRE7+G6N/ZIaczDyVHYAG/6mU=";
    })
    ./owners-file-name.patch
    ./permissions.patch
  ];
  postPatch = "rm -r docs/investigation";
  vendorHash = "sha256-R+pW3xcfpkTRqfS2ETVOwG8PZr0iH5ewroiF7u8hcYI=";
}
