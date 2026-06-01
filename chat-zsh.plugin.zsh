# After entering "# command described in natural language", press the Enter key, and the translated shell command will be displayed on the next line

# curl call LLM API
function generate_command_response() {
  command_desc="$1"
  endpoint="$2"
  api_key="$3"
  model_name="$4"

  local sys_prompt="You are a senior engineer who has mastered the command line ability of natural language translation. For the natural language input by the user, it is converted into a command line command according to the description content. Output may only contain executable commands, any other descriptive or explanatory text is prohibited. For the answer, you simply output a one-line translatable command, stripping out any description preceding the command. 1. For multi-line commands, use & or && to connect. 2. For dangerous commands, add DANGEROUS at the beginning of the command. 3. Never wrap output in markdown code fences."

  # Build the JSON payload via jq --arg to safely handle any special characters
  local payload
  payload=$(jq -n \
    --arg model "$model_name" \
    --arg desc "$command_desc" \
    --arg sys "$sys_prompt" \
    '{model:$model,messages:[{role:"system",content:$sys},{role:"user",content:"Install Node.js on Mac"},{role:"assistant",content:"brew install node"},{role:"user",content:"Delete all files or folders"},{role:"assistant",content:"DANGEROUS rm -rf *"},{role:"user",content:$desc}],temperature:0,stream:false}')

  # Send the request to the API (capture body + HTTP status)
  local response http_code
  response=$(curl -s -w '\n%{http_code}' "$endpoint" \
    --header "Authorization: Bearer $api_key" \
    --header "Content-Type: application/json" \
    --data "$payload")
  http_code=${response##*$'\n'}
  response=${response%$'\n'*}

  # Surface transport/auth/model errors instead of failing silently
  if [[ -z $response ]]; then
    print -u2 "chat-zsh: no response from $endpoint (network error?)"
    return 1
  fi
  local api_err
  api_err=$(printf '%s' "$response" | jq -r '.error.message // empty' 2>/dev/null)
  if [[ -n $api_err ]]; then
    print -u2 "chat-zsh: API error (HTTP $http_code): $api_err"
    return 1
  fi

  # Extract content; handle null/missing fields gracefully
  content=$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null | sed '/^```/d')
  if [[ -z $content ]]; then
    print -u2 "chat-zsh: empty completion (HTTP $http_code). Raw response: $response"
    return 1
  fi

  # Return the content
  echo "$content"
}

function prompt_to_command_sh() {
  local endpoint="https://api.openai.com/v1/chat/completions"
  # specially provided for user who can not directly access openai API, for example use a proxy endpoint or deepseek API
  if [[ -n $OPENAI_ENDPOINT ]]; then
    endpoint=$OPENAI_ENDPOINT
  fi
  echo $(generate_command_response "$1" "$endpoint" "$OPENAI_API_KEY" "$MODEL_NAME")
}

function zsh_line_finish() {
  local buffer=$BUFFER
  local first_two="${buffer:0:2}"
  local remaining="${buffer:2}"
  if [[ -n $buffer && $first_two = '##' ]]; then
    local new_str
    # curl default
    new_str=$(prompt_to_command_sh "$remaining")
    zle -U "$new_str"
    zle accept-line
  else
    zle accept-line
  fi
}
zle -N zsh_line_finish

bindkey '^M' zsh_line_finish
