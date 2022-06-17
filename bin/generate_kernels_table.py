#!/usr/bin/env python3
# REF: https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-devices/-/blob/52cbfb36/scripts/generate_kernels_table.py
import yaml # python3 -m pip install pyyaml --user
from datetime import datetime
import sys

OUTPUT_FILE = './md/kernels.md'
INPUT_FILE = './kernels.yml'
repo_msg = "\n_This table was generated automatically on {} from the [Kali ARM GitLab repository](https://gitlab.com/kalilinux/build-scripts/kali-arm)_\n".format(datetime.now().strftime("%Y-%B-%d %H:%M:%S"))
kernels_number = 0

def sanitize_content(data):
    result = ""
    lines = data.split('\n')
    for line in lines:
        if len(line) > 0 and line[0] != '#':
            result += line + '\n'
    return result

def generate_device_table(data):
    global kernels_number
    default = ""
    table  = "| Display Name | Kernel ID | Android Version | Linux Version | Kernel Version | Description | Features | Author | Source |\n"
    table += "|--------------|-----------|-----------------|---------------|----------------|-------------|----------|--------|--------|\n"
    for element in data:
        for kernel_name in element.keys():
            model = element[kernel_name]['model']
            for kernel in element[kernel_name]['kernels']:
                for version in kernel['versions']:
                    features = ""
                    i = 0
                    for f in version.get('features', default):
                        if i > 0:
                            features += ", "
                        features += f
                        i += 1
                    table += "| {} | {} | {} | {} | {} | {} | {} | {} | `{}` |\n".format(model,
                                                                                         kernel.get('id', default),
                                                                                         version.get('android', default),
                                                                                         version.get('linux', default),
                                                                                         version.get('kernel', default),
                                                                                         version.get('description', default),
                                                                                         features, version.get('author', default),
                                                                                         version.get('source', default))
    kernels_number = len(table.split('\n'))-3
    return table

def get_versions():
    with open(INPUT_FILE) as f:
        data = f.read()
        content = sanitize_content(data)
        return yaml.load(content, Loader=yaml.FullLoader)

def write_markdown():
    global kernels_number
    with open(OUTPUT_FILE, 'w') as g:
        meta  = '---\n'
        meta += 'title: Official Kali NetHunter Kernels\n'
        meta += '---\n\n'
        stats = "- The Kali NetHunter repository contains [**{}** kernels](nethunter-kernelstats.html)\n\n".format(str(kernels_number))
        g.write(str(meta))
        g.write(str(stats))
        g.write(generated_markdown)
        g.write(str(repo_msg))
        g.close()

def print_text():
    global kernels_number
    print('File: {} successfully written'.format(OUTPUT_FILE))
    print('Kernels: {}'.format(kernels_number))

res = get_versions()
generated_markdown = generate_device_table(res)
write_markdown()
print_text()
