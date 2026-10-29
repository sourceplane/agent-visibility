import base from "../../tooling/eslint/index.js";

export default [...base, { ignores: ["dist/**", ".wrangler/**"] }];
