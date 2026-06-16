import { sendPushToProfile } from './pushService.js';
import { sendSmsToProfile } from './smsService.js';

export async function dispatchNotification({
  profileId,
  title,
  message,
  level = 1,
  parentId = null,
}) {
  await sendPushToProfile(profileId, { title, message, level, parentId });
  await sendSmsToProfile(profileId, { title, message, level, parentId });
}
