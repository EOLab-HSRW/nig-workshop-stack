const userName = process.env.USER_NAME || "admin";
const passwordHash = process.env.NODE_RED_PASSWORD_HASH;
const credentialSecret = process.env.NODE_RED_CREDENTIAL_SECRET;

if (!passwordHash) {
  throw new Error("NODE_RED_PASSWORD_HASH is required. Run ./deploy.sh up so the hash is generated first.");
}

if (!credentialSecret) {
  throw new Error("NODE_RED_CREDENTIAL_SECRET is required.");
}

function normalizeRoot(value, fallback) {
  const raw = (value || fallback || "/").trim();
  if (raw === "/") return raw;
  return raw.startsWith("/") ? raw : `/${raw}`;
}


module.exports = {
  uiPort: process.env.PORT || 1880,

  credentialSecret,

  adminAuth: {
    type: "credentials",
    users: [
      {
        username: userName,
        password: passwordHash,
        permissions: "*",
      },
    ],
  },

  httpAdminRoot: normalizeRoot(process.env.NODE_RED_HTTP_ADMIN_ROOT, "/"),
  httpNodeRoot: normalizeRoot(process.env.NODE_RED_HTTP_NODE_ROOT, "/api"),

  logging: {
    console: {
      level: "info",

      metrics: false,
      audit: false,

    },
  },

  editorTheme: {
    projects: {
      enabled: false,

    },
  },
};
