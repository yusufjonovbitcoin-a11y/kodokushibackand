-- Ota-ona kutish sahifasi: so'rov holatini RLS dan mustaqil o'qish
CREATE OR REPLACE FUNCTION public.get_join_request_status(p_request_id UUID)
RETURNS TABLE (
  id UUID,
  status TEXT,
  requester_name TEXT,
  invite_code TEXT,
  requester_id UUID
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id, status, requester_name, invite_code, requester_id
  FROM public.join_requests
  WHERE id = p_request_id;
$$;

GRANT EXECUTE ON FUNCTION public.get_join_request_status(UUID) TO anon, authenticated;
