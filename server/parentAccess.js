import { isSupabaseAdminConfigured } from './supabaseAdmin.js';

export async function userCanAccessParent(supabase, userId, parentId) {
  if (!userId || !parentId) return false;

  const { data: parent } = await supabase
    .from('parents')
    .select('owner_id, numeric_id')
    .eq('id', parentId)
    .maybeSingle();

  if (!parent) return false;
  if (parent.owner_id === userId) return true;

  const { data: member } = await supabase
    .from('family_members')
    .select('id')
    .eq('parent_id', parentId)
    .eq('profile_id', userId)
    .maybeSingle();
  if (member) return true;

  const { data: settings } = await supabase
    .from('user_settings')
    .select('parent_invite_id, parent_self_profile')
    .eq('profile_id', userId)
    .maybeSingle();

  const linkedId =
    settings?.parent_invite_id?.trim() ||
    settings?.parent_self_profile?.numericId?.trim();
  if (linkedId && linkedId === parent.numeric_id) return true;

  const { data: joinReq } = await supabase
    .from('join_requests')
    .select('id')
    .eq('parent_id', parentId)
    .eq('requester_id', userId)
    .eq('status', 'approved')
    .maybeSingle();

  return Boolean(joinReq);
}

async function getAccessibleParentIds(supabase, userId) {
  const ids = new Set();

  const { data: owned } = await supabase
    .from('parents')
    .select('id')
    .eq('owner_id', userId);
  for (const row of owned ?? []) ids.add(row.id);

  const { data: members } = await supabase
    .from('family_members')
    .select('parent_id')
    .eq('profile_id', userId);
  for (const row of members ?? []) ids.add(row.parent_id);

  const { data: settings } = await supabase
    .from('user_settings')
    .select('parent_invite_id, parent_self_profile')
    .eq('profile_id', userId)
    .maybeSingle();

  const linkedId =
    settings?.parent_invite_id?.trim() ||
    settings?.parent_self_profile?.numericId?.trim();
  if (linkedId) {
    const { data: linkedParent } = await supabase
      .from('parents')
      .select('id')
      .eq('numeric_id', linkedId)
      .maybeSingle();
    if (linkedParent) ids.add(linkedParent.id);
  }

  const { data: joinReqs } = await supabase
    .from('join_requests')
    .select('parent_id')
    .eq('requester_id', userId)
    .eq('status', 'approved');
  for (const row of joinReqs ?? []) ids.add(row.parent_id);

  return [...ids];
}

export async function usersShareParentAccess(supabase, userA, userB) {
  if (!userA || !userB) return false;
  if (userA === userB) return true;

  const parentIds = await getAccessibleParentIds(supabase, userA);
  for (const parentId of parentIds) {
    if (await userCanAccessParent(supabase, userB, parentId)) return true;
  }
  return false;
}

export async function guardParentAccess(userId, parentId) {
  if (!parentId) return false;
  if (!isSupabaseAdminConfigured()) return true;
  const { getSupabaseAdmin } = await import('./supabaseAdmin.js');
  return userCanAccessParent(getSupabaseAdmin(), userId, parentId);
}

export async function guardUsersShareAccess(userA, userB) {
  if (!userA || !userB) return false;
  if (userA === userB) return true;
  if (!isSupabaseAdminConfigured()) return true;
  const { getSupabaseAdmin } = await import('./supabaseAdmin.js');
  return usersShareParentAccess(getSupabaseAdmin(), userA, userB);
}
