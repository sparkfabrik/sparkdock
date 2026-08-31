# shellcheck shell=bash

# shellcheck disable=SC2034 # Constants are consumed by scripts that source this file.
HARNESS_CONFIG_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/sparkdock/harness.json"
# shellcheck disable=SC2034 # Consumed by scripts that source this file.
SKILLS_ROOT_SUBDIR="skills"
# shellcheck disable=SC2034 # Consumed by scripts that source this file.
OPTIONAL_SKILLS_MANIFEST_SECTION="optional_skills"

validate_skill_category_name() {
    local category="$1"
    [[ "${category}" =~ ^[a-z0-9]+([a-z0-9-]*[a-z0-9])?$ ]]
}

list_enabled_skill_categories() {
    if [[ ! -f "${HARNESS_CONFIG_PATH}" ]]; then
        return
    fi

    python3 -c "
import json, re, sys

try:
    with open(sys.argv[1]) as file:
        data = json.load(file)
    if data.get('version') != 1:
        raise ValueError('unsupported config version')
    categories = data.get('enabled_skill_categories', [])
    if not isinstance(categories, list) or not all(isinstance(item, str) for item in categories):
        raise ValueError('enabled_skill_categories must be an array of strings')
    invalid = [
        item
        for item in categories
        if item == 'system' or re.fullmatch(r'[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?', item) is None
    ]
    if invalid:
        raise ValueError(f'invalid skill categories: {\", \".join(sorted(set(invalid)))}')
    for category in sorted(set(categories)):
        print(category)
except Exception as error:
    print(f'Invalid harness config: {error}', file=sys.stderr)
    sys.exit(1)
" "${HARNESS_CONFIG_PATH}"
}

set_skill_category_state() {
    local action="$1"
    local category="$2"

    python3 -c "
import json, os, sys, tempfile

config_path, action, category = sys.argv[1:]
data = {'version': 1, 'enabled_skill_categories': []}
if os.path.exists(config_path):
    with open(config_path) as file:
        data = json.load(file)
    if data.get('version') != 1:
        raise ValueError('unsupported config version')

categories = data.get('enabled_skill_categories', [])
if not isinstance(categories, list) or not all(isinstance(item, str) for item in categories):
    raise ValueError('enabled_skill_categories must be an array of strings')

enabled = set(categories)
if action == 'enable':
    enabled.add(category)
elif action == 'disable':
    enabled.discard(category)
else:
    raise ValueError(f'unsupported category action: {action}')

data['version'] = 1
data['enabled_skill_categories'] = sorted(enabled)
config_dir = os.path.dirname(config_path)
os.makedirs(config_dir, exist_ok=True)
with tempfile.NamedTemporaryFile('w', dir=config_dir, delete=False) as temporary:
    json.dump(data, temporary, indent=2)
    temporary.write('\n')
    temporary_path = temporary.name
os.replace(temporary_path, config_path)
" "${HARNESS_CONFIG_PATH}" "${action}" "${category}"
}

list_disabled_skills() {
    if [[ ! -f "${HARNESS_CONFIG_PATH}" ]]; then
        return
    fi

    python3 -c "
import json, re, sys

try:
    with open(sys.argv[1]) as file:
        data = json.load(file)
    if data.get('version') != 1:
        raise ValueError('unsupported config version')
    skills = data.get('disabled_skills', [])
    if not isinstance(skills, list) or not all(isinstance(item, str) for item in skills):
        raise ValueError('disabled_skills must be an array of strings')
    invalid = [
        item
        for item in skills
        if re.fullmatch(r'[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?', item) is None
    ]
    if invalid:
        raise ValueError(f'invalid disabled skills: {\", \".join(sorted(set(invalid)))}')
    for skill in sorted(set(skills)):
        print(skill)
except Exception as error:
    print(f'Invalid harness config: {error}', file=sys.stderr)
    sys.exit(1)
" "${HARNESS_CONFIG_PATH}"
}

set_skill_disabled_state() {
    local action="$1"
    local skill="$2"

    python3 -c "
import json, os, re, sys, tempfile

config_path, action, skill = sys.argv[1:]
data = {'version': 1}
if os.path.exists(config_path):
    with open(config_path) as file:
        data = json.load(file)
    if data.get('version') != 1:
        raise ValueError('unsupported config version')

skills = data.get('disabled_skills', [])
if not isinstance(skills, list) or not all(isinstance(item, str) for item in skills):
    raise ValueError('disabled_skills must be an array of strings')
invalid = [
    item
    for item in skills
    if re.fullmatch(r'[a-z0-9]+(?:[a-z0-9-]*[a-z0-9])?', item) is None
]
if invalid:
    raise ValueError(f'invalid disabled skills: {\", \".join(sorted(set(invalid)))}')

disabled = set(skills)
if action == 'disable':
    disabled.add(skill)
elif action == 'enable':
    disabled.discard(skill)
else:
    raise ValueError(f'unsupported skill action: {action}')

data['version'] = 1
data['disabled_skills'] = sorted(disabled)
config_dir = os.path.dirname(config_path)
os.makedirs(config_dir, exist_ok=True)
with tempfile.NamedTemporaryFile('w', dir=config_dir, delete=False) as temporary:
    json.dump(data, temporary, indent=2)
    temporary.write('\n')
    temporary_path = temporary.name
os.replace(temporary_path, config_path)
" "${HARNESS_CONFIG_PATH}" "${action}" "${skill}"
}

category_has_skills() {
    local category="$1"
    local category_dir="${CACHE_DIR}/${SKILLS_ROOT_SUBDIR}/${category}"
    local skill_dir

    [[ -d "${category_dir}" ]] || return 1
    for skill_dir in "${category_dir}"/*/; do
        [[ -f "${skill_dir}/SKILL.md" ]] && return 0
    done
    return 1
}

list_available_skill_categories() {
    local skills_root="${CACHE_DIR}/${SKILLS_ROOT_SUBDIR}"
    local category_dir category

    [[ -d "${skills_root}" ]] || return
    for category_dir in "${skills_root}"/*/; do
        [[ -d "${category_dir}" ]] || continue
        category="$(basename "${category_dir}")"
        [[ "${category}" == "system" ]] && continue
        validate_skill_category_name "${category}" || continue
        category_has_skills "${category}" && printf '%s\n' "${category}"
    done
}

count_category_skills() {
    local category="$1"
    local category_dir="${CACHE_DIR}/${SKILLS_ROOT_SUBDIR}/${category}"
    local count=0
    local skill_dir

    if [[ -d "${category_dir}" ]]; then
        for skill_dir in "${category_dir}"/*/; do
            [[ -f "${skill_dir}/SKILL.md" ]] || continue
            count=$((count + 1))
        done
    fi
    printf '%s\n' "${count}"
}
