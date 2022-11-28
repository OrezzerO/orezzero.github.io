<p>如果你对本文有任何疑惑, 或者本文有需要指正的地方, 可以看下 <a target="_blank" rel="noopener" href="https://github.com/OrezzerO/orezzero.github.io/issues">Issue 列表</a>是否有类似 issue, 如果没有的话欢迎 <a target="_blank" rel="noopener" href="https://github.com/OrezzerO/orezzero.github.io/issues/new">提交 Issue</a> 共同讨论.</p>


<div class="reward-container">
  <div>{{ page.reward_settings.comment }}</div>
  <button onclick="var qr = document.getElementById('qr'); qr.style.display = (qr.style.display === 'none') ? 'block' : 'none';">
    {{ __('reward.donate') }}
  </button>
  <div id="qr" style="display: none;">

    {%- for name, image in theme.reward %}
      {%- set builtin = ['wechatpay', 'alipay', 'paypal', 'bitcoin'] %}
      {%- if builtin.includes(name) %}
        {%- set translation = __('reward.' + name) %}
      {% else %}
        {%- set translation = name %}
      {%- endif %}
      <div style="display: inline-block;">
        <img src="{{ url_for(image) }}" alt="{{ author }} {{ translation }}">
        <p>{{ translation }}</p>
      </div>
    {%- endfor %}

  </div>
</div>
