FactoryBot.define do
  factory :app do
    transient { app_title { "Example app" } }
    after(:create) { |app, evaluator| app.update!(head_revision: app.revisions.create!(title: evaluator.app_title)) }
  end

  factory :notebook do
    association :app
    transient { notebook_title { "Example notebook" } }
    after(:create) { |notebook, evaluator| notebook.update!(head_revision: notebook.revisions.create!(title: evaluator.notebook_title)) }
  end
end
