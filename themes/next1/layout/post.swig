{% extends '_layout.swig' %}
{% import '_macro/sidebar.swig' as sidebar_template with context %}

{% block title %}{{ page.title }} | {{ title }}{% endblock %}

{% block class %}post posts-expand{% endblock %}

{% block content %}

  {{ partial('_macro/post.swig', {post: page}) }}

{% endblock %}
<p>如果你对本文有任何疑惑, 或者本文有需要指正的地方, 可以看下 <a target="_blank" rel="noopener" href="https://github.com/OrezzerO/orezzero.github.io/issues">Issue</a> 列表是否有类似 issue, 如果没有的话欢迎 <a target="_blank" rel="noopener" href="https://github.com/OrezzerO/orezzero.github.io/issues/new">提交 Issue</a> 共同讨论.</p>

{% block sidebar %}
  {{ sidebar_template.render(true) }}
{% endblock %}
