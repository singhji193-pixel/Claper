defmodule Claper.PostsTest do
  use Claper.DataCase

  alias Claper.Posts

  import Claper.{PostsFixtures, AccountsFixtures, EventsFixtures}

  alias Claper.Posts.Post

  describe "posts" do
    @invalid_attrs %{body: "a"}

    test "list_posts/0 returns all posts from an event" do
      post = post_fixture(%{}, [:event])
      assert Posts.list_posts(post.event.uuid, [:event]) == [post]
    end

    test "get_post!/1 returns the post with given id" do
      post = post_fixture(%{}, [:event])
      assert Posts.get_post!(post.uuid, [:event]) == post
    end

    test "create_post/1 with valid data creates a post" do
      user = user_fixture()
      event = event_fixture()
      valid_attrs = %{body: "some body", user_id: user.id, event_id: event.id, name: "some name"}

      assert {:ok, %Post{} = post} = Posts.create_post(event, valid_attrs)
      assert post.body == "some body"
    end

    test "create_post/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_post(%{}, @invalid_attrs)
    end

    test "update_post/2 with valid data updates the post" do
      post = post_fixture()
      update_attrs = %{body: "some updated body"}

      assert {:ok, %Post{} = post} = Posts.update_post(post, update_attrs)
      assert post.body == "some updated body"
    end

    test "update_post/2 with invalid data returns error changeset" do
      post = post_fixture(%{}, [:event])
      assert {:error, %Ecto.Changeset{}} = Posts.update_post(post, @invalid_attrs)
      assert post == Posts.get_post!(post.uuid, [:event])
    end

    test "delete_post/1 deletes the post" do
      post = post_fixture()
      assert {:ok, %Post{}} = Posts.delete_post(post)
      assert_raise Ecto.NoResultsError, fn -> Posts.get_post!(post.uuid) end
    end

    test "get_post_for_event/3 returns post when it belongs to the event" do
      event = event_fixture()
      post = post_fixture(%{event: event}, [:event])

      fetched_post = Posts.get_post_for_event(post.uuid, event.id, [:event])
      assert fetched_post.id == post.id
    end

    test "get_post_for_event/3 returns nil when post belongs to a different event" do
      event_a = event_fixture()
      event_b = event_fixture()
      post = post_fixture(%{event: event_a})

      assert is_nil(Posts.get_post_for_event(post.uuid, event_b.id))
    end

    test "get_post_for_event/3 returns nil for nonexistent post uuid" do
      event = event_fixture()
      assert is_nil(Posts.get_post_for_event(Ecto.UUID.generate(), event.id))
    end

    test "infers and lists explicit question and message kinds" do
      event = event_fixture()

      assert {:ok, question} =
               Posts.create_post(event, %{body: "What is next?", position: 0, name: "Avery"})

      assert {:ok, message} =
               Posts.create_post(event, %{body: "Thanks for sharing", position: 0, name: "Riley"})

      assert question.kind == "question"
      assert message.kind == "message"
      assert Enum.map(Posts.list_questions(event.uuid), & &1.id) == [question.id]
      assert Enum.map(Posts.list_posts_by_kind(event.uuid, "message"), & &1.id) == [message.id]
    end
  end

  describe "reactions" do
    alias Claper.Posts.Reaction

    import Claper.PostsFixtures

    @invalid_attrs %{icon: nil, post: nil}

    test "reacted_posts/3 from a post for a given user" do
      post = post_fixture()
      reaction = reaction_fixture(%{post: post, user_id: post.user_id})

      assert Posts.reacted_posts(post.event_id, post.user_id, reaction.icon) == [post.id]
    end

    test "create_reaction/1 with valid data creates a reaction" do
      post = post_fixture()
      valid_attrs = %{icon: "some icon", post: post, user_id: post.user_id}

      assert {:ok, %Reaction{} = reaction} = Posts.create_reaction(valid_attrs)
      assert reaction.icon == "some icon"
    end

    test "create_reaction/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Posts.create_reaction(@invalid_attrs)
    end

    test "delete_reaction/1 deletes the reaction" do
      post = post_fixture()
      reaction = reaction_fixture(%{post: post, user_id: post.user_id})

      assert {:ok, %Post{}} =
               Posts.delete_reaction(%{user_id: post.user_id, post: post, icon: "some icon"})

      assert_raise Ecto.NoResultsError, fn -> Posts.get_reaction!(reaction.id) end
    end

    test "toggles attendee reactions atomically and scopes the post to the event" do
      event = Claper.EventsFixtures.event_fixture()
      other_event = Claper.EventsFixtures.event_fixture()
      post = post_fixture(%{event: event}, [:event])

      assert {:ok, :added, updated_post} =
               Posts.toggle_attendee_reaction(event.id, "attendee-1", post.uuid, "👍")

      assert updated_post.like_count == post.like_count + 1

      assert {:ok, :removed, restored_post} =
               Posts.toggle_attendee_reaction(event.id, "attendee-1", post.uuid, "👍")

      assert restored_post.like_count == post.like_count

      assert {:error, :post_not_found} =
               Posts.toggle_attendee_reaction(other_event.id, "attendee-1", post.uuid, "👍")
    end
  end
end
