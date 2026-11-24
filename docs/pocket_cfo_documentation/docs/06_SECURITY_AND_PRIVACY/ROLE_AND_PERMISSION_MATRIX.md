# Profile Role and Permission Matrix

Proposed roles, to be approved before profile collaboration. Owner/Admin/Editor/Viewer are profile-scoped and are not global account roles.

| Action | Owner | Admin | Editor | Viewer |
|---|---:|---:|---:|---:|
| View profile records | Yes | Yes | Yes | Yes |
| Create/update draft financial records | Yes | Yes | Yes | No |
| Post/correct financial records | Yes | Yes | Policy-gated | No |
| Manage categories/budgets | Yes | Yes | Yes | No |
| Invite/remove members | Yes | Yes, policy-gated | No | No |
| Change profile settings/base currency | Yes | Limited | No | No |
| Transfer ownership | Yes, explicit re-auth | No | No | No |
| Delete/archive profile | Yes, explicit confirmation | No | No | No |

Define whether editors can see all accounts, whether sensitive account fields are masked, whether approvals are needed for high-impact changes, and what happens to records created by a member who is later removed. Server authorization must enforce every permission; UI visibility alone is insufficient.
