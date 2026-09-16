type requirement = {
  id : string;
  statement : string;
  depends_on : string list;
  acceptance : string option;
}

type artifact = {
  requirement_id : string;
  paths : string list;
}
